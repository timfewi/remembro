# Remembro Home-Manager Module
# Manages user-level daemon and shell integration.
#
# Usage:
#   { inputs, ... }: {
#     imports = [ inputs.remembro.homeManagerModules.default ];
#     services.remembro = {
#       enable = true;
#       shellIntegration = true;
#     };
#   }

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.remembro;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in
{
  options.services.remembro = {
    enable = mkEnableOption "Remembro daemon (home-manager)" // {
      default = true;
    };

    package = mkOption {
      type = types.package;
      default = pkgs.remembro;
      description = "Remembro package to use.";
    };

    shellIntegration = mkEnableOption "Shell hooks (zsh preexec/precmd)" // {
      default = true;
    };

    shell = mkOption {
      type = types.enum [
        "zsh"
        "bash"
        "fish"
      ];
      default = "zsh";
      description = "Shell to integrate with.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # User-level systemd service
    systemd.user.services.rembrodd = {
      Unit = {
        Description = "Remembro daemon — terminal command memory";
        Documentation = [ "https://github.com/timfewi/remembro" ];
        After = [ "sockets.target" ];
      };

      Service = {
        Type = "notify";
        ExecStart = "${cfg.package}/bin/rembrodd";
        Restart = "on-failure";
        RestartSec = 5;
        NotifyAccess = "main";
      };

      Install.WantedBy = [ "default.target" ];
    };

    # Shell integration
    programs.zsh.initExtra = mkIf (cfg.shellIntegration && cfg.shell == "zsh") ''
      # ── remembro shell hooks ─────────────────────────────────
      if command -v remembro-hook &>/dev/null; then
        eval "$(remembro-hook init zsh)"
      fi

      # Tab completion for rbro
      if command -v rbro &>/dev/null; then
        eval "$(rbro completion zsh 2>/dev/null)"
      fi
    '';

    programs.bash.initExtra = mkIf (cfg.shellIntegration && cfg.shell == "bash") ''
      # ── remembro shell hooks ─────────────────────────────────
      if command -v remembro-hook &>/dev/null; then
        eval "$(remembro-hook init bash)"
      fi
    '';

    programs.fish.interactiveShellInit = mkIf (cfg.shellIntegration && cfg.shell == "fish") ''
      # ── remembro shell hooks ─────────────────────────────────
      if command -v remembro-hook &>/dev/null
        remembro-hook init fish | source
      end
    '';
  };
}
