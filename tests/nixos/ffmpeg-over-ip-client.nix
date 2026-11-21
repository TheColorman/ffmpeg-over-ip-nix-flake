{
  pkgs,
  module,
  clientPackage,
}:
pkgs.testers.runNixOSTest {
  name = "ffmpeg-over-ip-client";

  nodes.machine =
    {
      config,
      lib,
      ...
    }:
    let
      jellyfinStub = pkgs.writeShellScriptBin "jellyfin" ''
        test -z "''${FFMPEG_OVER_IP_CLIENT_AUTH_SECRET:-}"
        test "$FFMPEG_OVER_IP_CLIENT_CONFIG" = "/run/ffmpeg-over-ip-client/config.json"
        ${pkgs.jq}/bin/jq -e \
          --arg address "gpu-host.example:5443" \
          --arg secret "vm-client-secret" \
          '.address == $address
            and .authSecret == $secret
            and .log == false
            and .fallbackToLocal
            and .fallbackRewrites == [["h264_nvenc", "libx264"]]
            and .debug' \
          "$FFMPEG_OVER_IP_CLIENT_CONFIG" >/dev/null
        echo "ffmpeg-over-ip client environment and config verified"
        exec ${pkgs.coreutils}/bin/sleep infinity
      '';
    in
    {
      imports = [
        module
      ];

      assertions = [
        {
          assertion = builtins.any (
            arg: builtins.isString arg && lib.hasInfix "ffmpeg-over-ip-client" arg
          ) config.services.jellyfin.package.makeWrapperArgs;
          message = "Jellyfin's FFmpeg wrapper must use the ffmpeg-over-ip client.";
        }
      ];

      services.jellyfin.enable = false;

      systemd.services.jellyfin = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${jellyfinStub}/bin/jellyfin";
          Restart = "no";
        };
      };

      services.ffmpeg-over-ip-client = {
        enableJellyfinIntegration = true;
        package = clientPackage;
        hostname = "gpu-host.example";
        port = 5443;
        authSecretFile = "/run/secrets/ffmpeg-over-ip-auth-secret";
        fallbackToLocal = true;
        fallbackRewrites = [
          [
            "h264_nvenc"
            "libx264"
          ]
        ];
        debug = true;
      };

      systemd.tmpfiles.rules = [
        "d /run/secrets 0700 root root -"
        "f /run/secrets/ffmpeg-over-ip-auth-secret 0600 root root - vm-client-secret"
      ];
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("jellyfin.service")
    machine.wait_until_succeeds(
        "journalctl -u jellyfin.service -b | "
        "grep -Fq 'ffmpeg-over-ip client environment and config verified'"
    )
    machine.succeed(
        "test \"$(stat -c %a /run/ffmpeg-over-ip-client/config.json)\" = 600"
    )
  '';
}
