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
    {
      imports = [ module ];

      assertions = [
        {
          assertion = builtins.any (
            arg: builtins.isString arg && lib.hasInfix "ffmpeg-over-ip-client" arg
          ) config.services.jellyfin.package.makeWrapperArgs;
          message = "Jellyfin's FFmpeg wrapper must use the ffmpeg-over-ip client.";
        }
        {
          assertion = builtins.elem config.services.ffmpeg-over-ip-client.fallbackPackage config.systemd.services.jellyfin.path;
          message = "The local Jellyfin FFmpeg package must be on the service PATH for fallback.";
        }
      ];

      services.jellyfin.enable = true;

      services.ffmpeg-over-ip-client = {
        enableJellyfinIntegration = true;
        package = clientPackage;
        hostname = "127.0.0.1";
        authSecretFile = "/run/secrets/ffmpeg-over-ip-auth-secret";
        fallbackToLocal = true;
        fallbackRewrites = [
          [
            "h264_nvenc"
            "libx264"
          ]
        ];
      };

      systemd.tmpfiles.rules = [
        "d /run/secrets 0700 root root -"
        "f /run/secrets/ffmpeg-over-ip-auth-secret 0600 root root - vm-test-secret"
      ];

      # Jellyfin refuses to start with less than 2 GiB free in its data dir.
      virtualisation.diskSize = 3 * 1024;
    };

  testScript = ''
    import json
    import shlex

    start_all()
    machine.wait_for_unit("jellyfin.service")
    machine.wait_for_open_port(8096)
    machine.wait_until_succeeds(
        "journalctl -b --unit jellyfin --grep 'Startup complete'"
    )
    machine.succeed("curl --fail http://localhost:8096/health | grep -q Healthy")

    jellyfin_path = machine.succeed(
        "pid=$(systemctl show jellyfin.service --property=MainPID --value); "
        "tr '\\0' '\\n' < /proc/$pid/environ | sed -n 's/^PATH=//p'"
    ).strip()
    fallback_bin = "${pkgs.jellyfin-ffmpeg}/bin"
    assert fallback_bin in jellyfin_path.split(":"), jellyfin_path

    def run_client(command):
        return machine.succeed(
            "su -s /bin/sh jellyfin -c "
            + shlex.quote(
                f"PATH={jellyfin_path} "
                "FFMPEG_OVER_IP_CLIENT_CONFIG=/run/ffmpeg-over-ip-client/config.json "
                f"{command}"
            )
        )

    version = run_client("${clientPackage}/bin/ffmpeg -version")
    assert "ffmpeg version" in version.lower(), version

    run_client(
        "${clientPackage}/bin/ffmpeg -hide_banner -loglevel error "
        "-f lavfi -i color=c=blue:s=64x64:d=1:r=5 -frames:v 5 -an "
        "-c:v h264_nvenc -f mpegts /tmp/ffmpeg-over-ip-fallback.ts -y"
    )

    probe = run_client(
        "${clientPackage}/bin/ffprobe -v error -select_streams v:0 "
        "-show_entries stream=codec_name,width,height -of json "
        "/tmp/ffmpeg-over-ip-fallback.ts"
    )
    stream = json.loads(probe)["streams"][0]
    assert stream["codec_name"] == "h264", stream
    assert stream["width"] == 64 and stream["height"] == 64, stream

    machine.succeed(
        "${pkgs.jq}/bin/jq -e "
        "' .address == \"127.0.0.1:5050\" "
        "and .authSecret == \"vm-test-secret\" "
        "and .log == false "
        "and .fallbackToLocal "
        "and .fallbackRewrites == [[\"h264_nvenc\", \"libx264\"]] ' "
        "/run/ffmpeg-over-ip-client/config.json >/dev/null"
    )
    machine.succeed(
        "test \"$(stat -c %a /run/ffmpeg-over-ip-client/config.json)\" = 600"
    )
    machine.fail(
        "systemctl show jellyfin.service --property=Environment --value | "
        "grep -Fq 'FFMPEG_OVER_IP_CLIENT_AUTH_SECRET='"
    )
  '';
}
