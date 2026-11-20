{
  ffmpeg_8-full,
  fetchFromGitHub,
  inputs,
}:

let
  version = "8.1.3-2";
  source = fetchFromGitHub {
    owner = "jellyfin";
    repo = "jellyfin-ffmpeg";
    tag = "v${version}";
    hash = "sha256-m6A/d7WszBzAqRAVkzN0PL0do9vZlceucDBgwT5VILE=";
  };
in
(ffmpeg_8-full.override {
  inherit source version;
}).overrideAttrs
  (old: {
    pname = "jellyfin-ffmpeg-over-ip";

    configureFlags = old.configureFlags ++ [
      "--extra-version=Jellyfin"
    ];

    postPatch = ''
      cp ${inputs.ffmpeg-over-ip}/fio/fio.c libavformat/fio.c
      cp ${inputs.ffmpeg-over-ip}/fio/fio.h libavformat/fio.h

      for patch in ${inputs.ffmpeg-over-ip}/patches/*.patch; do
        patch -p1 < "$patch"
      done

      for file in $(cat debian/patches/series); do
        patch -p1 < debian/patches/$file
      done

      ${old.postPatch or ""}
    '';

    meta = old.meta // {
      changelog = "https://github.com/jellyfin/jellyfin-ffmpeg/releases/tag/v${version}";
      description = "Jellyfin FFmpeg patched for ffmpeg-over-ip";
      homepage = "https://github.com/jellyfin/jellyfin-ffmpeg";
      pkgConfigModules = [ "libavutil" ];
    };
  })
