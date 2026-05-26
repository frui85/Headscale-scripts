# Client Connection Guide

[中文说明](CLIENTS.zh-CN.md)

Clients connect to the Headscale control server URL. Do not configure a separate DERP URL on clients.

## Server URL

Replace the example domain with your real domain:

```text
https://hs.example.com
```

Headscale sends the DERP map to clients after they connect. With the default installer configuration, that DERP map contains the embedded Headscale DERP region.

## No Separate DERP Domain by Default

The installer uses the same domain for Headscale and embedded DERP. Clients should not enter a DERP domain or DERP URL manually.

Use:

```text
https://hs.example.com
```

Do not use:

```text
https://derp.hs.example.com
```

A separate DERP domain is only for advanced deployments where DERP runs outside this Headscale server.

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

## User and Node Management

List users:

```bash
cd /opt/docker-compose.d/headscale-server
./scripts/manage.sh user list
```

List nodes:

```bash
./scripts/manage.sh node list
```

Register a node:

```bash
./scripts/manage.sh node register --key <REGISTER_KEY> --user default
```

Delete a node:

```bash
./scripts/manage.sh node delete --id <NODE_ID>
```

## Client Onboarding and Cleanup

Generate a single-use onboarding package:

```bash
cd /opt/docker-compose.d/headscale-server
./scripts/onboard.sh --user fr-mbp --expiration 24h
```

The client can join automatically with the printed auth key. No manual `nodes register` step is needed.

For short-lived clients, use an ephemeral key:

```bash
./scripts/onboard.sh --user temp-iphone --ephemeral --expiration 2h
```

Dry-run cleanup first:

```bash
./scripts/cleanup.sh --expired --delete-empty-users
```

Apply cleanup:

```bash
./scripts/cleanup.sh --apply --expired --delete-empty-users
```
