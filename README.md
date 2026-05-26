# Headscale + self-hosted DERP one-click installer

This repository installs a production-oriented Headscale stack with Docker Compose:

- Headscale control server
- Headscale embedded DERP enabled
- Caddy reverse proxy with automatic HTTPS
- SQLite persistence under `/opt/headscale/data`
- A permissive starter ACL file
- A generated client connection guide

By default, Headscale only publishes the embedded DERP region to clients. That means phone and desktop clients connect to the Headscale control server URL, then receive this server's DERP map from Headscale. You do not configure a separate DERP URL on clients.

## Quick start

Point your domain to the server first:

- `A` record: `hs.example.com -> server IPv4`
- optional `AAAA` record: `hs.example.com -> server IPv6`
- open TCP `80`, TCP `443`, and UDP `3478`

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/frui85/Headscale-scripts/main/install.sh \
  | sudo bash -s -- --domain hs.example.com --email admin@example.com --user default
```

Or clone and run locally:

```bash
git clone https://github.com/frui85/Headscale-scripts.git
cd Headscale-scripts
sudo bash install.sh --domain hs.example.com --email admin@example.com --user default
```

Useful options:

```bash
sudo bash install.sh \
  --domain hs.example.com \
  --email admin@example.com \
  --user default \
  --base-domain tailnet.example.com \
  --headscale-version 0.27.1 \
  --derp-ipv4 203.0.113.10
```

Use `--include-official-derp` if you want Tailscale's public DERP network as a fallback. Without it, your embedded DERP is the only DERP region and is therefore a single point of failure.

## Installed files

The installer writes everything under `/opt/headscale` by default:

```text
/opt/headscale/
  docker-compose.yml
  Caddyfile
  .env
  client-connect.txt
  config/
    config.yaml
    acl.hujson
  data/
  caddy_data/
  caddy_config/
```

Common commands:

```bash
cd /opt/headscale
docker compose ps
docker compose logs -f headscale
docker compose logs -f caddy
docker compose exec headscale headscale users list
docker compose exec headscale headscale nodes list
docker compose exec headscale headscale preauthkeys create --user default --reusable --expiration 24h
```

## Client connection

Use the Headscale URL, not a DERP URL:

```text
https://hs.example.com
```

Windows:

```powershell
tailscale login --login-server https://hs.example.com
```

macOS CLI:

```bash
tailscale login --login-server=https://hs.example.com
```

Linux:

```bash
tailscale up --login-server https://hs.example.com --authkey <AUTH_KEY>
```

Android:

```text
Tailscale app -> Accounts -> three-dot menu -> Use an alternate server -> https://hs.example.com
```

iOS:

```text
Tailscale app -> Add account/custom control server -> https://hs.example.com
```

After the client is registered, verify DERP from a desktop client:

```bash
tailscale debug derp-map
tailscale debug derp headscale
```

## Why clients do not configure DERP directly

Tailscale clients choose DERP servers from the DERP map sent by the coordination server. In this stack, Headscale is the coordination server and its embedded DERP region is automatically added to that map. Therefore:

1. Clients log in to `https://hs.example.com`.
2. Headscale registers or approves the node.
3. Headscale sends a DERP map containing the embedded `headscale` region.
4. Clients use UDP `3478` for STUN and HTTPS `443` for DERP relay fallback.

## References

- Headscale DERP reference: <https://headscale.net/0.27.1/ref/derp/>
- Headscale getting started: <https://docs.headscale.org/usage/getting-started/>
- Headscale Android client docs: <https://headscale.net/0.27.1/usage/connect/android/>
- Headscale Windows client docs: <https://docs.headscale.org/usage/connect/windows/>
- Tailscale custom control server docs: <https://tailscale.com/docs/how-to/set-up-custom-control-server>
