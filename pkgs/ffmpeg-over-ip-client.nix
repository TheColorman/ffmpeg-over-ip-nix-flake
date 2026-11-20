{
  ffmpeg-over-ip,
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "ffmpeg-over-ip-client";
  version = ffmpeg-over-ip.version;

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin
    ln -s ${ffmpeg-over-ip}/bin/ffmpeg-over-ip-client $out/bin/ffmpeg-over-ip-client
    ln -s ffmpeg-over-ip-client $out/bin/ffmpeg
    ln -s ffmpeg-over-ip-client $out/bin/ffprobe
  '';

  meta = ffmpeg-over-ip.meta // {
    description = "ffmpeg-over-ip client packaged for Jellyfin";
    license = lib.licenses.mit;
    mainProgram = "ffmpeg-over-ip-client";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
