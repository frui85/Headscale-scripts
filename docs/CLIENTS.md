# Client Connection Guide

Clients connect to the Headscale control server URL. Do not configure a separate DERP URL on clients.

## Server URL

Replace the example domain with your real domain:

```text
https://hs.example.com
```

Headscale sends the DERP map to clients after they connect. With the default installer configuration, that DERP map contains the embedded Headscale DERP region.

## Generate an Auth Key

On the server:

```bash
cd /opt/docker-compose.d/headscale-server
./scripts/genkey.sh --user default --expiration 24h
```

The command prints a preauth key. Use it for Linux and other non-interactive clients.

## Linux

```bash
sudo tailscale up --login-server https://hs.example.com --authkey <AUTH_KEY>
```

Verify status:

```bash
tailscale status
tailscale debug derp-map
```

## Windows

Open PowerShell:

```powershell
tailscale login --login-server https://hs.example.com
```

Finish the browser flow. If the machine should stay online without an active desktop login, enable unattended mode in the Tailscale tray preferences.

## macOS

CLI:

```bash
tailscale login --login-server=https://hs.example.com
```

GUI: open Tailscale, add a custom control server, and enter `https://hs.example.com`.

## Android

In the Tailscale app:

```text
Accounts -> three-dot menu -> Use an alternate server -> https://hs.example.com
```

If you use an auth key, set the alternate server first, then choose the auth key option from the account menu.

## iOS

In the Tailscale app, add an account with a custom control server and enter:

```text
https://hs.example.com
```

The exact menu changes between app versions. The important part is choosing the custom control server before completing login.

## DERP Verification

Run this on a connected desktop client:

```bash
tailscale debug derp-map
tailscale debug derp headscale
```

Expected result: the DERP map contains the `headscale` region or `Headscale Embedded DERP`.
