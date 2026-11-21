# ffmpeg-over-ip for Nix

This flake provides a combined NixOS module and packages for the ffmpeg-over-ip
client and server. The server package builds Jellyfin FFmpeg 8.1.3-2 from
Jellyfin's fork, applies the upstream ffmpeg-over-ip file-I/O patches, and then
applies the Jellyfin patches listed in `debian/patches/series`.
The combined module defines both server and Jellyfin client options, so import
`nixosModules.ffmpeg-over-ip` only once even when configuring both services.

## NixOS server

Add this flake as an input, then import its overlay and combined module:

```nix
{ inputs, ... }:
{
  nixpkgs.overlays = [ inputs.ffmpeg-over-ip.overlays.default ];
  imports = [ inputs.ffmpeg-over-ip.nixosModules.ffmpeg-over-ip ];

  services.ffmpeg-over-ip-server = {
    enable = true;
    authSecretFile = "/run/secrets/ffmpeg-over-ip-auth-secret";
    openFirewall = true;
    extraGroups = [ "render" "video" ];
  };
}
```

The secret file should contain only the shared secret. The module loads it as a
systemd credential and writes the server configuration to
`/run/ffmpeg-over-ip-server/config.json` with mode `0600`; the secret is not
embedded in the Nix store. Systemd creates this runtime directory for the
service. Server logs go to the journal and can be viewed with
`journalctl -u ffmpeg-over-ip-server`. The default listen address is
`0.0.0.0:5050`. Configure `firewallPorts` if you use a different TCP port.

## Jellyfin client

The client package supplies `ffmpeg-over-ip-client`, `ffmpeg`, and `ffprobe`.
Enable the NixOS Jellyfin integration to use it and configure the client:

```nix
{ inputs, ... }:
{
  nixpkgs.overlays = [ inputs.ffmpeg-over-ip.overlays.default ];
  imports = [ inputs.ffmpeg-over-ip.nixosModules.ffmpeg-over-ip ];

  services.ffmpeg-over-ip-client = {
    enableJellyfinIntegration = true;
    hostname = "gpu-host.example";
    authSecretFile = "/run/secrets/ffmpeg-over-ip-auth-secret";
    fallbackToLocal = true;
    fallbackRewrites = [
      [ "h264_nvenc" "libx264" ]
    ];
  };
}
```

Enable `services.jellyfin` separately. The required `hostname` and
`authSecretFile` options are checked when the integration is enabled.
`authSecretFile` should point to a runtime file containing only the shared
secret, not an environment-variable assignment. The module loads it as a
systemd credential and writes a mode-`0600` client config under `/run`, keeping
the secret out of the Nix store and the service environment.
`port` defaults to `5050`. Client logging is disabled by the module; the
`fallbackToLocal`, `fallbackRewrites`, and `debug` options configure its other
runtime behavior.

See the [upstream configuration reference](https://github.com/steelbrain/ffmpeg-over-ip/blob/v6.0.0/docs/configuration.md).

## Packages

- `packages.<system>.ffmpeg-over-ip-client`
- `packages.<system>.ffmpeg-over-ip-server`
- `packages.<system>.ffmpeg-over-ip-ffmpeg`
- `nixosModules.ffmpeg-over-ip` (includes server and Jellyfin client options)

## NixOS VM test

On Linux, run the VM integration tests with:

```sh
nix build .#checks.x86_64-linux.ffmpeg-over-ip-server
nix build .#checks.x86_64-linux.ffmpeg-over-ip-client
```

The `ffmpeg-over-ip-server` test boots the server module, checks credential
configuration and journal logging, rejects incorrect client authentication,
then transcodes and probes a sample through the packaged client and patched
FFmpeg. The `ffmpeg-over-ip-client` test verifies the Jellyfin environment and
runtime config wiring.
