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
    log = if builtins.isString cfg.log then cfg.log else false;
    inherit (cfg)
      debug
      fallbackRewrites
      fallbackToLocal
      ;
  };
  setupClient = pkgs.writeShellScript "ffmpeg-over-ip-client-setup" ''
    if [ ! -r "$CREDENTIALS_DIRECTORY/auth-secret" ]; then
      echo "The ffmpeg-over-ip client auth-secret systemd credential is missing" >&2
      exit 1
    fi

    umask 077
    if ! ${pkgs.jq}/bin/jq -e -n \
      --argjson settings ${lib.escapeShellArg clientConfig} \
      --rawfile authSecret "$CREDENTIALS_DIRECTORY/auth-secret" \
      '$settings + { authSecret: ($authSecret | rtrimstr("\n")) } | select(.authSecret != "")' \
      > ${clientConfigPath}; then
      echo "The ffmpeg-over-ip client auth-secret credential is empty or invalid" >&2
      exit 1
    fi
    chmod 0600 ${clientConfigPath}
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

    log = lib.mkOption {
      type = lib.types.oneOf [
        lib.types.bool
        lib.types.str
      ];
      default = false;
      example = "stderr";
      description = "Client log destination: false, stdout, stderr, or a file path.";
    };

    fallbackPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.jellyfin-ffmpeg;
      defaultText = lib.literalExpression "pkgs.jellyfin-ffmpeg";
      description = ''
        Local Jellyfin FFmpeg package added to the service PATH when
        fallbackToLocal is enabled.
      '';
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
      example = "/run/secrets/ffmpeg-over-ip-auth-secret";
      description = ''
        Required file containing only the shared authentication secret. It is
        loaded as a systemd credential and is not copied into the Nix store.
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
        assertion = cfg.log != true;
        message = "services.ffmpeg-over-ip-client.log must be false, stdout, stderr, or a file path.";
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
      environment.FFMPEG_OVER_IP_CLIENT_CONFIG = clientConfigPath;
      path = lib.optionals cfg.fallbackToLocal [ cfg.fallbackPackage ];

      serviceConfig = {
        LoadCredential = lib.mkIf (cfg.authSecretFile != null) [
          "auth-secret:${cfg.authSecretFile}"
        ];
        ExecStartPre = [ "${setupClient}" ];
        RuntimeDirectory = "ffmpeg-over-ip-client";
        RuntimeDirectoryMode = "0700";
      };
    };
  };
}
