{
  pkgs,
  lib,
  config,
  ...
}:

let
  # Flutter SDK pin. This replaces `fvm` from the original tech-spec: fvm fetches
  # unpatched SDK binaries that do not run on NixOS, and it would defeat the
  # reproducibility guarantee of the Nix store. See .constitution/tech-spec/stack.yaml.
  flutter = pkgs.flutterPackages.v3_44;

  # Native dependencies for the Flutter Linux desktop embedder (GTK). The current
  # phase targets desktop only; mobile toolchains are deliberately absent.
  linuxDesktopDeps = with pkgs; [
    gtk3
    glib
    pcre2
    libepoxy
    at-spi2-core
    # libmount.pc, required transitively by glib's pkg-config file. This also
    # puts util-linux's bin output on PATH, shadowing the host's `mount`,
    # `kill`, `dmesg` and friends inside the shell — as gtk3 and glib do for
    # `lp` and `gio`. Accepted: `util-linux.dev` does not avoid it (verified;
    # the bin output is propagated regardless).
    util-linux
    xorg.libX11
    # libglvnd, which owns the libGL.so.1 loader ABI. The driver implementations
    # come from the host (/run/opengl-driver on NixOS), so `mesa` is deliberately
    # not listed: it would add a closure without making GL work anywhere it
    # doesn't already.
    libGL
  ];

  # Native dependencies for the Rust core engine.
  #   openssl    -> rusqlite's `bundled-sqlcipher` links against it
  #   sqlcipher  -> CLI, for inspecting the encrypted index during development.
  #                 Note this floats independently of the SQLCipher that
  #                 `bundled-sqlcipher` vendors (currently CLI 4.16.0 vs
  #                 vendored 4.14.0). Compatible within 4.x; a nixpkgs bump
  #                 across a major boundary would break the inspect workflow.
  #
  # Note there is no Secret Service library here on purpose. `keyring` 4.x reaches
  # the OS enclave through `zbus`, which speaks the D-Bus wire protocol in pure
  # Rust; neither `libsecret` nor `libdbus` is required to build or run it.
  coreEngineDeps = with pkgs; [
    openssl
    sqlcipher
  ];

  # Hooks are written defensively on two axes. The Rust hook runs from `rust/`
  # when `rust/Cargo.toml` exists and otherwise accepts a root `Cargo.toml`; the
  # Dart hook runs when the root `pubspec.yaml` exists. If no supported manifest
  # exists, the relevant hook exits successfully, while an unexpected manifest
  # location fails loudly. Both invoke absolute store paths rather than bare
  # `cargo`/`dart`, so that a commit made outside the devenv shell (a GUI client,
  # an editor's built-in git, a terminal where direnv was never allowed) runs the
  # real check instead of failing with `command not found`.
  # `toolchainPackage`, not `toolchain.cargo`: when `toolchainFile` is set, the
  # combined toolchain lands in the former, while the latter silently falls back
  # to nixpkgs' cargo — a different version from the one the shell provides.
  cargo = "${config.languages.rust.toolchainPackage}/bin/cargo";
  dart = "${flutter}/bin/dart";

  # The guards distinguish "no supported manifest exists" (skip) from "a
  # manifest exists somewhere unexpected" (fail loudly). A bare
  # `[ -f rust/Cargo.toml ] || exit 0` would turn a layout change into a green
  # commit with no checks run and nothing said about it.
  #
  # They exclude `.constitution/` for the same reason the hooks do — the spec
  # keeps source-shaped files as documentation (see contracts/ffi_api.rs), and a
  # manifest example landing there must not hard-block every commit.
  #
  # The `git ls-files` result is assigned rather than tested inline. `| grep -q`
  # can SIGPIPE the upstream into a 141 under `pipefail`, and `[ -z "$(...)" ]`
  # discards the substitution's exit status outright — both would read a failing
  # git as "no manifest found" and silently skip every check, which is the exact
  # failure this guard exists to prevent. An assignment propagates the status.
  rustHook =
    name: command:
    pkgs.writeShellScript "burlmd-${name}" ''
      set -euo pipefail
      # An absolute cargo is not sufficient outside the shell: cargo finds rustc
      # beside itself but not a linker, and any crate with a build script then
      # dies on `linker `cc` not found`. libsqlite3-sys — reached through
      # bundled-sqlcipher, the centre of this stack — has one, and additionally
      # needs libclang for bindgen and pkg-config/openssl. Supply the minimum so
      # the outside-the-shell path actually runs the check it promises.
      # bash and coreutils are in here because the nixpkgs cc wrapper is itself a
      # bash script that shells out; without them the linker fails with a
      # `collect2: ld returned 127` that is far harder to read than the original
      # `command not found`.
      export PATH="${pkgs.stdenv.cc}/bin:${pkgs.pkg-config}/bin:${pkgs.bash}/bin:${pkgs.coreutils}/bin:$PATH"
      export LIBCLANG_PATH="${pkgs.llvmPackages.libclang.lib}/lib"
      export PKG_CONFIG_PATH="${pkgs.openssl.dev}/lib/pkgconfig''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
      if [ -f rust/Cargo.toml ]; then
        cd rust
      elif [ ! -f Cargo.toml ]; then
        manifests=$(git ls-files -- '*Cargo.toml' ':!.constitution/**') || {
          echo "burlmd: git ls-files failed; refusing to skip checks." >&2
          exit 1
        }
        if [ -n "$manifests" ]; then
          echo "burlmd: Cargo.toml found outside rust/ or the repository root." >&2
          echo "        Update the rustHook guard in devenv.nix." >&2
          exit 1
        fi
        exit 0
      fi
      exec ${cargo} ${command}
    '';

  # Takes a body rather than a bare command, so the format hook can scope its
  # paths while sharing the manifest guard.
  dartHook =
    name: body:
    pkgs.writeShellScript "burlmd-${name}" ''
      set -euo pipefail
      if [ ! -f pubspec.yaml ]; then
        manifests=$(git ls-files -- '*pubspec.yaml' ':!.constitution/**') || {
          echo "burlmd: git ls-files failed; refusing to skip checks." >&2
          exit 1
        }
        if [ -n "$manifests" ]; then
          echo "burlmd: pubspec.yaml found outside the repository root." >&2
          echo "        Update the dartHook guard in devenv.nix." >&2
          exit 1
        fi
        exit 0
      fi
      ${body}
    '';

  # `dart format` has no --exclude and only skips directories whose name starts
  # with a dot, so a bare `dart format .` reaches the Dart sources FRB scaffolds
  # under rust_builder/cargokit/ — vendored third-party glue whose own README
  # says to ignore it. Formatting only the directories this project owns keeps
  # the gate off code we do not control. `dart analyze` needs the equivalent via
  # `analyzer.exclude` in analysis_options.yaml, which CORE-A001 must add.
  dartFormatBody = ''
    # Anything .dart outside the owned roots is a guard failure, not a silent
    # skip — the same rule the manifest guards above follow. rust_builder/ is
    # excluded because that is where the vendored cargokit sources live.
    stray=$(git ls-files -- '*.dart' \
      ':!lib/**' ':!test/**' ':!integration_test/**' ':!test_driver/**' ':!rust_builder/**' ':!.constitution/**') || {
      echo "burlmd: git ls-files failed; refusing to skip checks." >&2
      exit 1
    }
    if [ -n "$stray" ]; then
      echo "burlmd: Dart sources outside lib/ and test/:" >&2
      echo "$stray" | sed 's/^/          /' >&2
      echo "        Add the directory to dartFormatBody in devenv.nix." >&2
      exit 1
    fi

    paths=()
    for d in lib test integration_test test_driver; do
      [ -d "$d" ] && paths+=("$d")
    done
    if [ ''${#paths[@]} -eq 0 ]; then
      exit 0
    fi
    # --output=none: `--set-exit-if-changed` only sets the exit code, it does
    # not stop `dart format` rewriting in place. Without this the hook silently
    # mutates the working tree while the README presents it as a check, and an
    # auto-fix to a partially staged file can collide with prek's stash/restore.
    exec ${dart} format --output=none --set-exit-if-changed "''${paths[@]}"
  '';
in
{
  # --- Toolchains -----------------------------------------------------------

  languages.rust = {
    enable = true;
    # Pinned in ./rust-toolchain.toml so rustup users converge on the same
    # toolchain. Do not add `channel`/`version` here; they are mutually exclusive.
    toolchainFile = ./rust-toolchain.toml;
  };

  languages.dart = {
    enable = true;
    # The Flutter distribution ships its own Dart SDK; using it avoids a version
    # skew between `dart analyze` and the SDK Flutter actually compiles against.
    package = flutter;
  };

  # --- Packages -------------------------------------------------------------

  packages =
    with pkgs;
    [
      flutter
      flutter_rust_bridge_codegen # FRB v2 code generator (ADR-001)

      # Build tooling required by the Flutter desktop build and by rust bindgen.
      pkg-config
      cmake
      ninja
      # Flutter's Linux desktop build requires clang. The stdenv gcc wrapper
      # still wins the PATH race and `CC` is `gcc` (verified in the shell), so
      # the Rust half of the monorepo and every `cc`-crate build script compile
      # with gcc while Flutter's CMake step uses clang. Mixing is fine in
      # practice; it is recorded here so nobody debugging a build script starts
      # from the wrong premise about which compiler they are actually using.
      clang

      git

      # Manual visual-verification tooling (Wayland). `grim` captures a real
      # screenshot of the running app; `wtype` injects keystrokes into the
      # focused window. Used to actually look at rendered pixels and exercise
      # live typing, rather than only asserting widget properties in
      # `flutter test`. Not part of the CI/build path.
      grim
      wtype
    ]
    ++ coreEngineDeps
    ++ lib.optionals pkgs.stdenv.isLinux linuxDesktopDeps;

  # --- Environment ----------------------------------------------------------

  env = {
    # bindgen (pulled in by rusqlite/sqlcipher) locates libclang through this.
    LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";

    # Deliberately no LD_LIBRARY_PATH. CMake bakes an RPATH into the Flutter
    # desktop bundle, so it resolves every library on its own (verified with
    # `ldd` on a release build with the variable unset). Exporting it would apply
    # to every process in the shell, and on a non-NixOS host it forces nix-built
    # libc-linked sonames into distro binaries like git, curl and ssh.
    #
    # Enabling devenv's `android` module breaks this invariant — it appends
    # libglvnd, vulkan-loader and the NDK/build-tools lib dirs to
    # LD_LIBRARY_PATH. That is one reason the Android SDK is not pinned here;
    # see ANDROID_HOME below.

    # Pin Android SDK discovery to a path that deliberately holds no SDK.
    # Flutter otherwise scans well-known home-directory locations and silently
    # adopts whatever SDK a contributor happens to have installed — the one part
    # of the toolchain devenv.lock could not govern. With these set, discovery is
    # deterministic and identical on every machine: `flutter doctor` reports
    # "Unable to locate Android SDK" instead of picking up ~/.android/sdk.
    #
    # A real pinned SDK belongs here when mobile is unshelved, at versions
    # current at that time. Doing it now would cost a 14.9 GiB closure on every
    # desktop-only checkout, for platforms and an NDK that will be years stale
    # before anything compiles against them.
    ANDROID_HOME = "${config.env.DEVENV_ROOT}/.sentinels/no-android-sdk";
    ANDROID_SDK_ROOT = "${config.env.DEVENV_ROOT}/.sentinels/no-android-sdk";

    # Same reasoning for the web target, which is no more in scope than mobile.
    # Left unset, Flutter resolves a browser off the host PATH and reports a
    # green `[✓] Chrome` that devenv.lock does not govern — a per-machine result
    # from ambient state, which is exactly what the Android pair above closes.
    CHROME_EXECUTABLE = "${config.env.DEVENV_ROOT}/.sentinels/no-chrome";
  };

  # The banner goes to stderr. On stdout it corrupts every non-interactive
  # `devenv shell -- <cmd>` invocation — CI steps, `direnv exec`, and any
  # `devenv shell -- cargo metadata | jq` style pipeline.
  #
  # Each probe is captured before defaulting: `$(cmd | cut ...) || echo '?'`
  # never fires, because `||` binds to `cut`, which exits 0 on empty input. The
  # fallback would silently print an empty field in exactly the broken case it
  # exists to surface.
  enterShell = ''
    _v() { "$@" 2>/dev/null | head -n1 | cut -d' ' -f2; }
    _flutter=$(_v flutter --version)
    _rustc=$(_v rustc --version)
    _frb=$(_v flutter_rust_bridge_codegen --version)
    echo "burlmd — local-first, Git-backed notes" >&2
    echo "  flutter ''${_flutter:-?}  |  rustc ''${_rustc:-?}  |  frb ''${_frb:-?}" >&2
    unset -f _v
    unset _flutter _rustc _frb
  '';

  # --- Quality gates (see .constitution/tech-spec/guidelines.md) ------------

  # Every hook is named under a `burlmd-` prefix. Bare ids such as `dart-analyze`
  # and `clippy` already exist as builtins in git-hooks.nix, and defining one
  # merges with the builtin rather than replacing it — inheriting its `types`
  # filter, which pre-commit intersects with `files`. That silently narrowed
  # `dart analyze` to Dart files only, dropping the `pubspec.yaml` case the
  # pattern was widened for.
  git-hooks.hooks = {
    # devenv.nix is the one source file in the repository that no other hook
    # covers, and it is currently the only source file at all. Unlike the
    # language hooks this one runs with pass_filenames = true and rewrites in
    # place, so the .constitution/ exclusion is load-bearing rather than
    # cosmetic: without it, a .nix file kept in the spec as documentation would
    # be reformatted by a commit that merely touched it.
    nixfmt-rfc-style = {
      enable = true;
      excludes = [ "^\\.constitution/" ];
    };

    burlmd-rust-fmt = {
      enable = true;
      name = "cargo fmt";
      entry = toString (rustHook "cargo-fmt" "fmt --all -- --check");
      files = "\\.rs$";
      # The tech-spec's FFI contract is a .rs file that is documentation, not
      # crate source; editing it must not trigger a build gate.
      excludes = [ "^\\.constitution/" ];
      pass_filenames = false;
      language = "system";
    };

    burlmd-rust-clippy = {
      enable = true;
      name = "cargo clippy";
      # --workspace so this matches `cargo fmt --all`'s scope; without it clippy
      # only covers default workspace members.
      entry = toString (rustHook "cargo-clippy" "clippy --workspace --all-targets -- -D warnings");
      # rust-toolchain.toml is included deliberately: a commit that only bumps
      # the compiler is the change most likely to break the build, and it would
      # otherwise pass through no Rust gate at all.
      files = "(\\.rs|Cargo\\.(toml|lock)|rust-toolchain\\.toml)$";
      excludes = [ "^\\.constitution/" ];
      pass_filenames = false;
      language = "system";
    };

    burlmd-dart-fmt = {
      enable = true;
      name = "dart format";
      entry = toString (dartHook "dart-format" dartFormatBody);
      files = "\\.dart$";
      excludes = [ "^\\.constitution/" ];
      pass_filenames = false;
      language = "system";
    };

    burlmd-dart-analyze = {
      enable = true;
      name = "dart analyze";
      entry = toString (dartHook "dart-analyze" "exec ${dart} analyze");
      files = "(\\.dart|pubspec\\.yaml)$";
      excludes = [ "^\\.constitution/" ];
      pass_filenames = false;
      language = "system";
    };
  };
}
