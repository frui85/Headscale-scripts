# Architecture

## Components

```text
Internet clients
      |
      | HTTPS 443 / STUN UDP 3478
      v
Public server
      |
      +-- caddy
      |     - listens on TCP 80 and 443
      |     - requests HTTPS certificates automatically
      |     - stores certificate data in ./certs
      |     - reverse proxies HTTPS traffic to headscale:8080
      |
      +-- headscale
            - listens on 8080 inside Docker
            - stores SQLite state in ./data
            - exposes embedded DERP/STUN on UDP 3478
            - sends DERP map to clients
```

## Install Directory

Default:

```text
/opt/docker-compose.d/headscale-server
```

Runtime layout:

```text
/opt/docker-compose.d/headscale-server/
  docker-compose.yml
  Caddyfile
  .env
  client-connect.txt
  config/
    config.yaml
    derp.yaml
    acl.hujson
  data/
  certs/
  caddy_config/
  backups/
  scripts/
```

## Certificate Flow

The installer writes `.env` with:

```env
DOMAIN=hs.example.com
ACME_EMAIL=admin@example.com
```

Caddy receives those values through Docker Compose. It listens on TCP `80` and `443`, completes ACME validation, and stores certificate data in the mounted `./certs` directory.

## DERP Flow

Clients do not connect to a separate DERP configuration endpoint. They connect to Headscale:

```text
client -> https://hs.example.com -> caddy -> headscale
```

Headscale returns a DERP map. The default config enables embedded DERP:

```yaml
derp:
  server:
    enabled: true
    stun_listen_addr: "0.0.0.0:3478"
  urls: []
```

With this default, the embedded Headscale DERP is the only DERP region. Passing `--include-official-derp` during installation adds the official Tailscale DERP map as fallback.

## Persistence

Persistent state is local to the install directory:

- `data/`: Headscale SQLite database and private keys
- `certs/`: Caddy certificate data
- `caddy_config/`: Caddy internal config state
- `config/`: Headscale config, DERP map file, ACL file
- `backups/`: tarball backups produced by `scripts/backup.sh`
