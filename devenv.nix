{
  pkgs,
  lib,
  config,
  ...
}:

let
  # Flutter SDK pin. This replaces `fvm` from the original tech-spec: fvm fetches
  # unpatched SDK binaries that do not run on NixOS, and it would defeat the
  # reproducibility guarantee of the Nix store. See tech-spec/stack.md.
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

  # Hooks are written defensively on two axes. They no-op until the manifest they
  # need exists, because this repository is intentionally empty of application
  # code until CORE-A001 lands; and they invoke absolute store paths rather than
  # bare `cargo`/`dart`, so that a commit made outside the devenv shell (a GUI
  # client, an editor's built-in git, a terminal where direnv was never allowed)
  # runs the real check instead of failing with `command not found`.
  # `toolchainPackage`, not `toolchain.cargo`: when `toolchainFile` is set, the
  # combined toolchain lands in the former, while the latter silently falls back
  # to nixpkgs' cargo — a different version from the one the shell provides.
  cargo = "${config.languages.rust.toolchainPackage}/bin/cargo";
  dart = "${flutter}/bin/dart";

  rustHook =
    name: command:
    pkgs.writeShellScript "burlmd-${name}" ''
      set -euo pipefail
      [ -f rust/Cargo.toml ] || exit 0
      cd rust
      exec ${cargo} ${command}
    '';

  dartHook =
    name: command:
    pkgs.writeShellScript "burlmd-${name}" ''
      set -euo pipefail
      [ -f pubspec.yaml ] || exit 0
      exec ${dart} ${command}
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
  };

  enterShell = ''
    echo "burlmd — local-first, Git-backed notes"
    echo "  flutter $(flutter --version 2>/dev/null | head -n1 | cut -d' ' -f2 || echo '?')  |  rustc $(rustc --version 2>/dev/null | cut -d' ' -f2 || echo '?')  |  frb $(flutter_rust_bridge_codegen --version 2>/dev/null | cut -d' ' -f2 || echo '?')"
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
    # covers, and it is currently the only source file at all.
    nixfmt-rfc-style.enable = true;

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
      entry = toString (rustHook "cargo-clippy" "clippy --all-targets -- -D warnings");
      files = "(\\.rs|Cargo\\.(toml|lock))$";
      excludes = [ "^\\.constitution/" ];
      pass_filenames = false;
      language = "system";
    };

    burlmd-dart-fmt = {
      enable = true;
      name = "dart format";
      entry = toString (dartHook "dart-format" "format --set-exit-if-changed .");
      files = "\\.dart$";
      pass_filenames = false;
      language = "system";
    };

    burlmd-dart-analyze = {
      enable = true;
      name = "dart analyze";
      entry = toString (dartHook "dart-analyze" "analyze");
      files = "(\\.dart|pubspec\\.yaml)$";
      pass_filenames = false;
      language = "system";
    };
  };
}
