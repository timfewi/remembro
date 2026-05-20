{
  description = "A CLI tool to remember and search for shell commands.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      mkPkg = system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          script = builtins.readFile ./remembro;
        in
        rec {
          remembro = pkgs.writeShellApplication {
            name = "remembro";
            runtimeInputs = [ pkgs.jq ];
            excludeShellChecks = [ "SC2016" ];
            text = script;
            meta = {
              description = "A CLI tool to remember and search for shell commands";
              longDescription = ''
                remembro stores shell commands in a local JSON database and
                lets you list, search, add, edit, and delete them from the terminal.
              '';
              homepage = "https://github.com/timfewi/remembro";
              license = pkgs.lib.licenses.mit;
              maintainers = with pkgs.lib.maintainers; [ ];
              platforms = pkgs.lib.platforms.unix;
              mainProgram = "remembro";
            };
          };

          rbro = pkgs.writeShellApplication {
            name = "rbro";
            runtimeInputs = [ remembro ];
            text = ''exec remembro "$@"'';
            meta = remembro.meta // { mainProgram = "rbro"; };
          };

          default = remembro;
        };
    in
    {
      packages = forAllSystems mkPkg;

      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        {
          default = pkgs.mkShell {
            packages = [ pkgs.jq ];
          };
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}
