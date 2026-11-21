{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.ffmpeg-over-ip-server;
  jsonSettings = builtins.toJSON {
    inherit (cfg)
      address
      debug
      rewrites
      ;
    log = "stderr";
  };
  writeConfig = pkgs.writeShellScript "ffmpeg-over-ip-server-config" ''
    ${pkgs.jq}/bin/jq -n \
      --argjson settings ${lib.escapeShellArg jsonSettings} \
      --rawfile authSecret "$CREDENTIALS_DIRECTORY/auth-secret" \
      '$settings + { authSecret: ($authSecret | rtrimstr("\n")) }' \
      > /run/ffmpeg-over-ip-server/config.json
    chmod 0600 /run/ffmpeg-over-ip-server/config.json
  '';
in
{
  options.services.ffmpeg-over-ip-server = {
    enable = lib.mkEnableOption "the ffmpeg-over-ip server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.ffmpeg-over-ip-server;
      defaultText = lib.literalExpression "pkgs.ffmpeg-over-ip-server";
      description = "Server package, including the patched ffmpeg and ffprobe binaries.";
    };

    address = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0:5050";
      description = "Listen address in host:port or unix:/path form.";
    };

    authSecretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/ffmpeg-over-ip-auth-secret";
      description = ''
        Path to a runtime file containing the shared authentication secret.
        The secret is loaded as a systemd credential and is not copied into
        the Nix store.
      '';
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Log original and rewritten ffmpeg arguments.";
    };

    rewrites = lib.mkOption {
      type = lib.types.listOf (lib.types.listOf lib.types.str);
      default = [ ];
      example = [
        [
          "h264_nvenc"
          "h264_qsv"
        ]
      ];
      description = "Ordered ffmpeg argument rewrite pairs.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        FFOIP_READAHEAD_BYTES = "4194304";
        FFOIP_RANGE_CACHE_BYTES = "536870912";
      };
      description = "Additional environment variables passed to the server and its ffmpeg children.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the configured TCP firewall ports.";
    };

    firewallPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ 5050 ];
      description = "TCP ports opened when openFirewall is enabled.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "ffmpeg-over-ip";
      description = "User under which the server and ffmpeg run.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "ffmpeg-over-ip";
      description = "Primary group for the server process.";
    };

    extraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "render"
        "video"
      ];
      description = "Supplementary groups, for example render and video for GPU access.";
    };

    createUser = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Create the dedicated system user and group.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.authSecretFile != null;
        message = "services.ffmpeg-over-ip-server.authSecretFile must be set when the server is enabled.";
      }
      {
        assertion = builtins.all (rewrite: builtins.length rewrite == 2) cfg.rewrites;
        message = "Each services.ffmpeg-over-ip-server.rewrites entry must contain exactly two strings.";
      }
    ];

    users.users = lib.mkIf cfg.createUser {
      "${cfg.user}" = {
        isSystemUser = true;
        group = cfg.group;
        description = "ffmpeg-over-ip server";
        extraGroups = cfg.extraGroups;
      };
    };

    users.groups = lib.mkIf cfg.createUser {
      "${cfg.group}" = { };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall cfg.firewallPorts;

    systemd.services.ffmpeg-over-ip-server = {
      description = "ffmpeg-over-ip server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      environment = cfg.environment;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        SupplementaryGroups = cfg.extraGroups;
        RuntimeDirectory = "ffmpeg-over-ip-server";
        RuntimeDirectoryMode = "0700";
        LoadCredential = lib.mkIf (cfg.authSecretFile != null) [
          "auth-secret:${cfg.authSecretFile}"
        ];
        ExecStartPre = "${writeConfig}";
        ExecStart = "${cfg.package}/bin/ffmpeg-over-ip-server --config /run/ffmpeg-over-ip-server/config.json";
        Restart = "on-failure";
        RestartSec = "5s";
        UMask = "0077";
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      };
    };
  };
}
