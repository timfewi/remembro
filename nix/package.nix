# Remembro v2 Nix package
# Builds the Rust workspace: rembrodd (daemon) + rbro (CLI) + remembro-mcp + remembro-hook

{
  lib,
  rustPlatform,
  pkg-config,
  openssl,
  sqlite,
  installShellFiles,
  ...
}:

rustPlatform.buildRustPackage rec {
  pname = "remembro";
  version = "2.0.0-dev";
  src = ../.;
  cargoLock.lockFile = ../Cargo.lock;

  nativeBuildInputs = [
    pkg-config
    installShellFiles
  ];
  buildInputs = [
    openssl
    sqlite
  ];

  # Build the entire workspace
  cargoBuildFlags = [ "--workspace" ];

  postInstall = ''
    # Install shell integration script
    install -Dm755 ${../shell-integration.sh} $out/bin/remembro-hook-wrapper

    # Generate shell completions
    $out/bin/rbro completion zsh > remembro.zsh 2>/dev/null || true
    $out/bin/rbro completion bash > remembro.bash 2>/dev/null || true
    installShellCompletion --zsh remembro.zsh
    installShellCompletion --bash remembro.bash
  '';

  meta = with lib; {
    description = "Terminal daemon to remember and search shell commands";
    longDescription = ''
      remembro v2 is a background daemon (rembrodd) that stores, indexes, and
      searches shell commands. It provides fast vector search via 'rbro !<query>',
      auto-captures commands from shell hooks and AI agents, and integrates
      with NixOS via systemd user services.
    '';
    homepage = "https://github.com/timfewi/remembro";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.unix;
    mainProgram = "rbro";
  };
}
