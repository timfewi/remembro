{
  description = "A terminal daemon to remember, search, and capture shell commands.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
      crane,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      mkPkg =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
          };
          rustToolchain = pkgs.rust-bin.stable.latest.default.override {
            extensions = [
              "rust-src"
              "clippy"
              "rustfmt"
            ];
          };
          craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

          src = craneLib.cleanCargoSource (craneLib.path ./.);
          commonArgs = {
            inherit src;
            buildInputs =
              with pkgs;
              [
                openssl
                sqlite
              ]
              ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ ];
            nativeBuildInputs = with pkgs; [ pkg-config ];
          };

          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        in
        rec {
          remembro = craneLib.buildPackage (
            commonArgs
            // {
              inherit cargoArtifacts;
              cargoExtraArgs = "--workspace";
              meta = with pkgs.lib; {
                description = "Terminal daemon to remember and search shell commands";
                license = licenses.mit;
                platforms = platforms.unix;
                mainProgram = "rbro";
              };
            }
          );
          default = remembro;
        };

    in
    {
      packages = forAllSystems mkPkg;

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
          };
          rustToolchain = pkgs.rust-bin.stable.latest.default.override {
            extensions = [
              "rust-src"
              "clippy"
              "rustfmt"
            ];
          };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              rustToolchain
              cargo-llvm-cov
              cargo-watch
              cargo-nextest
              sqlx-cli
              openssl
              pkg-config
              sqlite
              jq
            ];
            RUST_BACKTRACE = 1;
            RUST_LOG = "info";
            shellHook = ''
              echo "━━━ remembro v2 dev shell ━━━"
              echo "  Build: nix build .#remembro"
              echo "  Test:  cargo nextest run"
              echo "  Lint:  cargo clippy"
            '';
          };
        }
      );

      # NixOS module
      nixosModules = {
        remembro = import ./nix/remembro-nixos-module.nix;
        default = self.nixosModules.remembro;
      };

      # Home-manager module
      homeManagerModules = {
        remembro = import ./nix/remembro-home-manager.nix;
        default = self.homeManagerModules.remembro;
      };

      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt-rfc-style);
    };
}
