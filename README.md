# ffmpeg-over-ip for Nix

This flake provides a NixOS server module and packages for the ffmpeg-over-ip
client and server. The server package builds Jellyfin FFmpeg 8.1.3-2 from
Jellyfin's fork, applies the upstream ffmpeg-over-ip file-I/O patches, and then
applies the Jellyfin patches listed in `debian/patches/series`.

## NixOS server

Add this flake as an input, then import its overlay and module:

```nix
{ inputs, ... }:
{
  nixpkgs.overlays = [ inputs.ffmpeg-over-ip.overlays.default ];
  imports = [ inputs.ffmpeg-over-ip.nixosModules.ffmpeg-over-ip-server ];

  services.ffmpeg-over-ip-server = {
    enable = true;
    authSecretFile = "/run/secrets/ffmpeg-over-ip-auth-secret";
    openFirewall = true;
    extraGroups = [ "render" "video" ];
  };
}
```

The secret file should contain only the shared secret. The module loads it as a
systemd credential and writes the server configuration under `/run`; the secret
is not embedded in the Nix store. The default listen address is
`0.0.0.0:5050`. Configure `firewallPorts` if you use a different TCP port.
For file logging, set `log` to a filename directly under
`/var/log/ffmpeg-over-ip-server` (for example,
`/var/log/ffmpeg-over-ip-server/server.log`); the module creates that writable
directory while keeping the rest of the filesystem read-only to the service.

## Jellyfin client

The client package supplies `ffmpeg-over-ip-client`, `ffmpeg`, and `ffprobe`.
Override Jellyfin's bundled FFmpeg package so its wrapper points at the client:

```nix
{ pkgs, ... }:
{
  services.jellyfin.package = pkgs.jellyfin.override {
    jellyfin-ffmpeg = pkgs.ffmpeg-over-ip-client;
  };

  systemd.services.jellyfin = {
    environment.FFMPEG_OVER_IP_CLIENT_ADDRESS = "gpu-host.example:5050";
    serviceConfig.EnvironmentFile = [ "/run/secrets/ffmpeg-over-ip-client.env" ];
  };
}
```

The environment file should define `FFMPEG_OVER_IP_CLIENT_AUTH_SECRET` and be
provided by a runtime secret manager rather than stored in the Nix store. The
client also supports the upstream `/etc/ffmpeg-over-ip.client.jsonc` config
file; see the [upstream configuration reference](https://github.com/steelbrain/ffmpeg-over-ip/blob/v6.0.0/docs/configuration.md).

## Packages

- `packages.<system>.ffmpeg-over-ip-client`
- `packages.<system>.ffmpeg-over-ip-server`
- `packages.<system>.ffmpeg-over-ip-ffmpeg`
- `nixosModules.ffmpeg-over-ip-server`

## NixOS VM test

On Linux, run the server integration test with:

```sh
nix build .#checks.x86_64-linux.ffmpeg-over-ip-server
```

The test boots the NixOS module, checks credential-based configuration and
file logging, rejects incorrect client authentication, then transcodes and
probes a sample through the packaged client and patched FFmpeg.
