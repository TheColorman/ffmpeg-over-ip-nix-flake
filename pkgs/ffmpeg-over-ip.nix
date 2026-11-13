{ inputs, buildGoModule, ... }:
buildGoModule (finalAttrs: {
  pname = "ffmpeg-over-ip";
  version = "6.0.0";

  src = inputs.ffmpeg-over-ip;

  vendorHash = null;

  meta = {
    description = "Connect to remote ffmpeg servers";
    homepage = "https://github.com/steelbrain/ffmpeg-over-ip";
  };
})
