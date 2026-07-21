{ pkgs, lib, ... }:

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
    util-linux # libmount, pulled in transitively by glib's pkg-config file
    xorg.libX11
    libGL
    mesa
  ];

  # Native dependencies for the Rust core engine.
  #   openssl    -> rusqlite's `bundled-sqlcipher` links against it
  #   libsecret  -> the `keyring` crate's Secret Service backend on Linux
  #   sqlcipher  -> CLI, for inspecting the encrypted index during development
  coreEngineDeps = with pkgs; [
    openssl
    libsecret
    sqlcipher
  ];

  # Hooks are written defensively: this repository is intentionally empty of
  # application code until CORE-A001 lands, so each hook no-ops until the
  # corresponding manifest exists.
  rustHook =
    name: command:
    pkgs.writeShellScript "burlmd-${name}" ''
      set -euo pipefail
      [ -f rust/Cargo.toml ] || exit 0
      cd rust
      exec ${command}
    '';

  dartHook =
    name: command:
    pkgs.writeShellScript "burlmd-${name}" ''
      set -euo pipefail
      [ -f pubspec.yaml ] || exit 0
      exec ${command}
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
      clang

      git
    ]
    ++ coreEngineDeps
    ++ lib.optionals pkgs.stdenv.isLinux linuxDesktopDeps;

  # --- Environment ----------------------------------------------------------

  env = {
    # bindgen (pulled in by rusqlite/sqlcipher) locates libclang through this.
    LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";

    # The compiled Linux desktop bundle resolves GTK/GL at runtime.
    LD_LIBRARY_PATH = lib.optionalString pkgs.stdenv.isLinux (
      lib.makeLibraryPath (linuxDesktopDeps ++ coreEngineDeps)
    );
  };

  enterShell = ''
    echo "burlmd — local-first, Git-backed notes"
    echo "  flutter $(flutter --version 2>/dev/null | head -n1 | cut -d' ' -f2 || echo '?')  |  $(rustc --version)  |  frb $(flutter_rust_bridge_codegen --version 2>/dev/null | cut -d' ' -f2 || echo '?')"
  '';

  # --- Quality gates (see .constitution/tech-spec/guidelines.md) ------------

  git-hooks.hooks = {
    rust-fmt = {
      enable = true;
      name = "cargo fmt";
      entry = toString (rustHook "cargo-fmt" "cargo fmt --all -- --check");
      files = "\\.rs$";
      pass_filenames = false;
      language = "system";
    };

    rust-clippy = {
      enable = true;
      name = "cargo clippy";
      entry = toString (rustHook "cargo-clippy" "cargo clippy --all-targets -- -D warnings");
      files = "(\\.rs|Cargo\\.(toml|lock))$";
      pass_filenames = false;
      language = "system";
    };

    dart-fmt = {
      enable = true;
      name = "dart format";
      entry = toString (dartHook "dart-format" "dart format --set-exit-if-changed .");
      files = "\\.dart$";
      pass_filenames = false;
      language = "system";
    };

    dart-analyze = {
      enable = true;
      name = "dart analyze";
      entry = toString (dartHook "dart-analyze" "dart analyze");
      files = "(\\.dart|pubspec\\.yaml)$";
      pass_filenames = false;
      language = "system";
    };
  };
}
