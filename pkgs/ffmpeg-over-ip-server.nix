{
  ffmpeg-over-ip,
  ffmpeg-over-ip-ffmpeg,
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "ffmpeg-over-ip-server";
  version = ffmpeg-over-ip.version;

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin
    install -m755 ${ffmpeg-over-ip}/bin/ffmpeg-over-ip-server $out/bin/ffmpeg-over-ip-server
    ln -s ${ffmpeg-over-ip-ffmpeg}/bin/ffmpeg $out/bin/ffmpeg
    ln -s ${ffmpeg-over-ip-ffmpeg}/bin/ffprobe $out/bin/ffprobe
  '';

  meta = {
    description = "ffmpeg-over-ip server with patched Jellyfin FFmpeg";
    homepage = "https://github.com/steelbrain/ffmpeg-over-ip";
    license = lib.toList ffmpeg-over-ip-ffmpeg.meta.license ++ [ lib.licenses.mit ];
    mainProgram = "ffmpeg-over-ip-server";
    platforms = lib.platforms.linux;
  };
}
