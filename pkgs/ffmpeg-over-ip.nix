{
  inputs,
  buildGoModule,
  lib,
  ...
}:
buildGoModule (finalAttrs: {
  pname = "ffmpeg-over-ip";
  version = "6.0.0";

  src = inputs.ffmpeg-over-ip;

  subPackages = [
    "cmd/client"
    "cmd/server"
  ];

  vendorHash = null;

  postInstall = ''
    mv $out/bin/client $out/bin/ffmpeg-over-ip-client
    mv $out/bin/server $out/bin/ffmpeg-over-ip-server
  '';

  meta = {
    description = "Connect to remote ffmpeg servers";
    homepage = "https://github.com/steelbrain/ffmpeg-over-ip";
    license = lib.licenses.mit;
    mainProgram = "ffmpeg-over-ip-client";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
