# Headscale-scripts

[中文说明](README.zh-CN.md)

Headscale + embedded DERP Docker Compose one-click installer.

本仓库用于一键安装 Headscale 自建控制服务器，并启用 Headscale embedded DERP。客户端只需要连接 Headscale 域名，DERP map 由 Headscale 自动下发。

## Directory

```text
Headscale-scripts/
├── install.sh
├── uninstall.sh
├── update.sh
├── docker-compose.yml
├── .env.example
├── Caddyfile
├── README.md
├── LICENSE
├── scripts/
│   ├── healthcheck.sh
│   ├── genkey.sh
│   └── backup.sh
├── config/
│   ├── config.yaml
│   ├── derp.yaml
│   └── acl.hujson
└── docs/
    ├── CLIENTS.md
    ├── TROUBLESHOOT.md
    └── ARCHITECTURE.md
```

## Quick Install

Before installing:

- Point your domain to the server, for example `hs.example.com`.
- Open TCP `80` and `443`.
- Open UDP `3478`.

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/frui85/Headscale-scripts/main/install.sh \
  | sudo bash -s -- --domain hs.example.com --email admin@example.com --user default
```

Default install directory:

```text
/opt/docker-compose.d/headscale-server
```

Caddy automatically requests HTTPS certificates for the domain passed to `--domain`. Certificate data is mounted under:

```text
/opt/docker-compose.d/headscale-server/certs
```

## Local Install

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
  --install-dir /opt/docker-compose.d/headscale-server \
  --headscale-version 0.27.1 \
  --authkey-expiration 24h \
  --derp-ipv4 203.0.113.10
```

Use `--include-official-derp` if you want Tailscale's official DERP network as fallback. Without it, only the embedded DERP region is published.

## Server Commands

```bash
cd /opt/docker-compose.d/headscale-server
docker compose ps
docker compose logs -f headscale
docker compose logs -f caddy
./scripts/healthcheck.sh
./scripts/manage.sh user list
./scripts/manage.sh node list
./scripts/genkey.sh --user default
./scripts/backup.sh
```

User and node CRUD helper:

```bash
./scripts/manage.sh user create fr-mbp
./scripts/manage.sh user list
./scripts/manage.sh user rename --name fr-mbp fr-macbook
./scripts/manage.sh user delete --name fr-macbook --force

./scripts/manage.sh node list
./scripts/manage.sh node register --key <REGISTER_KEY> --user fr-mbp
./scripts/manage.sh node rename --id 2 fr-mbp
./scripts/manage.sh node move --id 2 --user default
./scripts/manage.sh node expire --id 2 --force
./scripts/manage.sh node delete --id 2 --force
```

Update:

```bash
sudo bash update.sh --headscale-version 0.27.1
```

Uninstall but keep data:

```bash
sudo bash uninstall.sh
```

Uninstall and delete config, data, certs, and backups:

```bash
sudo bash uninstall.sh --purge
```

## Client Connection

Use the Headscale URL, not a DERP URL:

```text
https://hs.example.com
```

Linux:

```bash
sudo tailscale up --login-server https://hs.example.com --authkey <AUTH_KEY>
```

Windows:

```powershell
tailscale login --login-server https://hs.example.com
```

macOS:

```bash
tailscale login --login-server=https://hs.example.com
```

Android and iOS: add a custom or alternate control server and enter `https://hs.example.com`.

## DERP Domain

This installer does not ask for a separate DERP domain by default.

The default deployment uses one domain for both Headscale and the embedded DERP service:

```text
https://hs.example.com
```

Clients log in to that Headscale URL. Headscale then sends a DERP map that contains the embedded `headscale` DERP region. For a single-server install, you only need:

- TCP `443` for HTTPS and DERP relay traffic
- UDP `3478` for STUN
- `server_url` set to `https://hs.example.com`
- `derp.server.enabled: true`

A separate DERP domain is only needed when you run DERP independently from Headscale, deploy DERP on another server, build multi-region DERP such as `derp-hk.example.com` and `derp-sg.example.com`, or intentionally separate the control plane from relay traffic.

More detail:

- [Client connection guide](docs/CLIENTS.md)
- [Troubleshooting](docs/TROUBLESHOOT.md)
- [Architecture](docs/ARCHITECTURE.md)
- [中文新手完整使用文档](docs/USER_GUIDE.zh-CN.md)
