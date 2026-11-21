{
  pkgs,
  module,
  serverPackage,
  clientPackage,
}:
pkgs.testers.runNixOSTest {
  name = "ffmpeg-over-ip-server";

  nodes.machine =
    { ... }:
    {
      imports = [ module ];

      services.ffmpeg-over-ip-server = {
        enable = true;
        package = serverPackage;
        address = "127.0.0.1:5050";
        authSecretFile = "/run/secrets/ffmpeg-over-ip-auth-secret";
        debug = true;
        log = "/var/log/ffmpeg-over-ip-server/server.log";
        rewrites = [
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
    };

  testScript = ''
    import json

    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("ffmpeg-over-ip-server.service")
    machine.wait_until_succeeds("grep -Fq 'listening on 127.0.0.1:5050' /var/log/ffmpeg-over-ip-server/server.log")

    machine.succeed("test \"$(stat -c %a /run/ffmpeg-over-ip-server/config.json)\" = 600")
    machine.succeed("grep -Fq 'vm-test-secret' /run/ffmpeg-over-ip-server/config.json")
    machine.succeed("test \"$(systemctl show ffmpeg-over-ip-server.service --property=User --value)\" = ffmpeg-over-ip")

    machine.fail(
        "FFMPEG_OVER_IP_CLIENT_ADDRESS=127.0.0.1:5050 "
        "FFMPEG_OVER_IP_CLIENT_AUTH_SECRET=wrong-secret "
        "${clientPackage}/bin/ffmpeg -version"
    )
    machine.wait_until_succeeds("grep -Fq 'auth failed' /var/log/ffmpeg-over-ip-server/server.log")

    machine.succeed(
        "FFMPEG_OVER_IP_CLIENT_ADDRESS=127.0.0.1:5050 "
        "FFMPEG_OVER_IP_CLIENT_AUTH_SECRET=vm-test-secret "
        "${clientPackage}/bin/ffmpeg -nostdin -hide_banner -loglevel error "
        "-f lavfi -i color=c=blue:s=64x64:d=1:r=5 -frames:v 5 -an "
        "-c:v h264_nvenc -f mpegts /tmp/ffmpeg-over-ip-test.ts -y"
    )

    probe = machine.succeed(
        "FFMPEG_OVER_IP_CLIENT_ADDRESS=127.0.0.1:5050 "
        "FFMPEG_OVER_IP_CLIENT_AUTH_SECRET=vm-test-secret "
        "${clientPackage}/bin/ffprobe -v error -select_streams v:0 "
        "-show_entries stream=codec_name,width,height -of json "
        "/tmp/ffmpeg-over-ip-test.ts"
    )
    stream = json.loads(probe)["streams"][0]
    assert stream["codec_name"] == "h264", stream
    assert stream["width"] == 64 and stream["height"] == 64, stream

    machine.succeed("grep -Fq '[debug] rewritten args:' /var/log/ffmpeg-over-ip-server/server.log")
  '';
}
