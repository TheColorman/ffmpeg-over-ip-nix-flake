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
      { lib, ... }: {
        imports = [ inputs.pkgs-by-name.flakeModule ];

        systems = lib.systems.flakeExposed;

        perSystem = { self', ... }: {
          pkgsDirectory = ./pkgs;

          packages.default = self'.packages.ffmpeg-over-ip;
        };
      }
    );
}
