{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.ffmpeg-over-ip-client;
  address = "${cfg.hostname}:${toString cfg.port}";
  clientConfigPath = "/run/ffmpeg-over-ip-client/config.json";
  clientConfig = builtins.toJSON {
    inherit address;
    authSecret = "";
    log = false;
    inherit (cfg)
      debug
      fallbackRewrites
      fallbackToLocal
      ;
  };
  setupClient = pkgs.writeShellScript "ffmpeg-over-ip-client-setup" ''
    if [ -z "''${FFMPEG_OVER_IP_CLIENT_AUTH_SECRET:-}" ]; then
      echo "FFMPEG_OVER_IP_CLIENT_AUTH_SECRET is missing from the Jellyfin EnvironmentFile" >&2
      exit 1
    fi

    ${lib.optionalString (cfg.fallbackRewrites != [ ]) ''
      ${pkgs.jq}/bin/jq -n \
        --argjson settings ${lib.escapeShellArg clientConfig} \
        --arg authSecret "$FFMPEG_OVER_IP_CLIENT_AUTH_SECRET" \
        '$settings + { authSecret: $authSecret }' \
        > ${clientConfigPath}
      chmod 0600 ${clientConfigPath}
    ''}
  '';
in
{
  options.services.ffmpeg-over-ip-client = {
    enableJellyfinIntegration = lib.mkEnableOption "ffmpeg-over-ip for Jellyfin";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.ffmpeg-over-ip-client;
      defaultText = lib.literalExpression "pkgs.ffmpeg-over-ip-client";
      description = "The ffmpeg-over-ip client package used as Jellyfin's FFmpeg package.";
    };

    hostname = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "gpu-host.example";
      description = "Required server hostname. IPv6 literals must be enclosed in brackets.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5050;
      description = "TCP port used by the ffmpeg-over-ip server.";
    };

    authSecretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/ffmpeg-over-ip-client.env";
      description = ''
        Required systemd EnvironmentFile containing
        FFMPEG_OVER_IP_CLIENT_AUTH_SECRET. Keep this file outside the Nix store.
      '';
    };

    fallbackToLocal = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run Jellyfin's local FFmpeg if the remote server is unavailable.";
    };

    fallbackRewrites = lib.mkOption {
      type = lib.types.listOf (lib.types.listOf lib.types.str);
      default = [ ];
      example = [
        [
          "h264_nvenc"
          "libx264"
        ]
      ];
      description = "Ordered argument rewrite pairs applied only to local fallback commands.";
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Log original and rewritten arguments when local fallback runs.";
    };
  };

  config = lib.mkIf cfg.enableJellyfinIntegration {
    assertions = [
      {
        assertion = cfg.hostname != null && cfg.hostname != "";
        message = "services.ffmpeg-over-ip-client.hostname must be set when Jellyfin integration is enabled.";
      }
      {
        assertion = cfg.authSecretFile != null && cfg.authSecretFile != "";
        message = "services.ffmpeg-over-ip-client.authSecretFile must be set when Jellyfin integration is enabled.";
      }
      {
        assertion = builtins.all (rewrite: builtins.length rewrite == 2) cfg.fallbackRewrites;
        message = "Each services.ffmpeg-over-ip-client.fallbackRewrites entry must contain exactly two strings.";
      }
    ];

    services.jellyfin.package = lib.mkDefault (
      pkgs.jellyfin.override {
        jellyfin-ffmpeg = cfg.package;
      }
    );

    systemd.services.jellyfin = {
      environment = {
        FFMPEG_OVER_IP_CLIENT_ADDRESS = address;
        FFMPEG_OVER_IP_CLIENT_FALLBACK_TO_LOCAL = lib.boolToString cfg.fallbackToLocal;
        FFMPEG_OVER_IP_CLIENT_DEBUG = lib.boolToString cfg.debug;
      }
      // lib.optionalAttrs (cfg.fallbackRewrites != [ ]) {
        FFMPEG_OVER_IP_CLIENT_CONFIG = clientConfigPath;
      };

      serviceConfig = {
        EnvironmentFile = lib.optional (cfg.authSecretFile != null) cfg.authSecretFile;
        ExecStartPre = [ "${setupClient}" ];
      }
      // lib.optionalAttrs (cfg.fallbackRewrites != [ ]) {
        RuntimeDirectory = "ffmpeg-over-ip-client";
        RuntimeDirectoryMode = "0700";
      };
    };
  };
}
