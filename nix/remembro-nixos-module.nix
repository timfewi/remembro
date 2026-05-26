# Remembro NixOS Module
# Provides systemd user service, socket activation, and daemon configuration.
#
# Usage:
#   { inputs, ... }: {
#     imports = [ inputs.remembro.nixosModules.default ];
#     services.remembro = {
#       enable = true;
#       user = "tim";
#       vectorSearch.enable = true;
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
    enable = mkEnableOption "Remembro daemon (rembrodd)";

    package = mkOption {
      type = types.package;
      default = pkgs.remembro;
      description = "Remembro package to use.";
    };

    user = mkOption {
      type = types.str;
      default = "tim";
      description = "User the daemon runs as.";
    };

    group = mkOption {
      type = types.str;
      default = "users";
      description = "Group for the daemon socket.";
    };

    vectorSearch = {
      enable = mkEnableOption "Vector search with local ONNX model" // {
        default = true;
      };

      model = mkOption {
        type = types.str;
        default = "all-MiniLM-L6-v2";
        description = "Embedding model name (downloaded on first run).";
      };
    };

    capture = {
      shellHooks = mkEnableOption "Inject zsh preexec hooks" // {
        default = true;
      };

      agentSocket = mkEnableOption "Agent capture socket" // {
        default = true;
      };
    };

    log = {
      level = mkOption {
        type = types.enum [
          "error"
          "warn"
          "info"
          "debug"
          "trace"
        ];
        default = "info";
        description = "Log level.";
      };

      maxFiles = mkOption {
        type = types.int;
        default = 7;
        description = "Number of rotated log files to keep.";
      };

      maxSize = mkOption {
        type = types.str;
        default = "10M";
        description = "Max log file size before rotation.";
      };
    };
  };

  config = mkIf cfg.enable {
    # Ensure the package is available
    environment.systemPackages = [ cfg.package ];

    # Systemd user service for the daemon
    systemd.user.services.rembrodd = {
      enable = true;

      description = "Remembro daemon — terminal command memory";
      documentation = [ "https://github.com/timfewi/remembro" ];
      after = [ "sockets.target" ];

      serviceConfig = {
        Type = "notify";
        ExecStart = "${cfg.package}/bin/rembrodd";
        Restart = "on-failure";
        RestartSec = 5;
        NotifyAccess = "main";

        # Security hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = "%h/.remembro";
        NoNewPrivileges = true;

        # Resource limits
        CPUQuota = "50%";
        MemoryMax = "256M";

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
      };

      wantedBy = [ "default.target" ];
    };

    # Socket activation for the daemon
    systemd.user.sockets.rembrodd = {
      enable = true;

      description = "Remembro daemon socket";
      documentation = [ "https://github.com/timfewi/remembro" ];

      socketConfig = {
        ListenStream = "%t/remembro/rembro.sock";
        SocketMode = "0600";
        DirectoryMode = "0700";
        RemoveOnStop = true;
      };

      wantedBy = [ "sockets.target" ];
    };

    # Agent capture socket (world-writable for agent integration)
    systemd.user.sockets.remembro-capture = mkIf cfg.capture.agentSocket {
      enable = true;

      description = "Remembro agent capture socket";
      documentation = [ "https://github.com/timfewi/remembro" ];

      socketConfig = {
        ListenStream = "%t/remembro/capture.sock";
        SocketMode = "0666";
        DirectoryMode = "0711";
        RemoveOnStop = true;
      };

      wantedBy = [ "sockets.target" ];
    };

    # Shell hook injection via environment
    environment.shellInit = mkIf cfg.capture.shellHooks ''
      if command -v remembro-hook &>/dev/null && [ -S "$XDG_RUNTIME_DIR/remembro/rembro.sock" ]; then
        eval "$(remembro-hook init zsh)"
      fi
    '';

    # Log rotation for standalone JSONL logs
    services.logrotate = {
      enable = true;
      settings = {
        "${config.users.users.${cfg.user}.home}/.remembro/logs/rembrodd.jsonl" = {
          daily = true;
          rotate = cfg.log.maxFiles;
          size = cfg.log.maxSize;
          compress = true;
          notifempty = true;
          missingok = true;
          postrotate = ''
            systemctl --user kill -s USR1 rembrodd
          '';
          su = "${cfg.user} ${cfg.group}";
        };
      };
    };
  };
}
