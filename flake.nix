{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-26.05";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    pkgs-by-name.url = "github:drupol/pkgs-by-name-for-flake-parts";
    ffmpeg-over-ip = {
      url = "github:steelbrain/ffmpeg-over-ip/v6.0.0";
      flake = false;
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      { lib, withSystem, ... }: {
        imports = [ inputs.pkgs-by-name.flakeModule ];

        systems = lib.systems.flakeExposed;

        flake = {
          nixosModules.ffmpeg-over-ip-server = import ./modules/ffmpeg-over-ip-server.nix;

          overlays.default =
            final: prev:
            withSystem prev.stdenv.hostPlatform.system (
              { config, ... }: {
                ffmpeg-over-ip = config.packages.ffmpeg-over-ip;
                ffmpeg-over-ip-client = config.packages.ffmpeg-over-ip-client;
                ffmpeg-over-ip-ffmpeg = config.packages.ffmpeg-over-ip-ffmpeg;
                ffmpeg-over-ip-server = config.packages.ffmpeg-over-ip-server;
              }
            );
        };

        perSystem = { self', ... }: {
          pkgsDirectory = ./pkgs;

          packages.default = self'.packages.ffmpeg-over-ip;
        };
      }
    );
}
