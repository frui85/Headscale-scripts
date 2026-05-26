# Troubleshooting

## Check Service Health

On the server:

```bash
cd /opt/docker-compose.d/headscale-server
./scripts/healthcheck.sh
```

View logs:

```bash
docker compose logs -f headscale
docker compose logs -f caddy
```

## Caddy Cannot Issue a Certificate

Check these items first:

- The `A` or `AAAA` record points to this server.
- TCP `80` and `443` are open in the cloud security group.
- TCP `80` and `443` are open in the host firewall.
- No other process is already using ports `80` or `443`.

Certificate data is stored under:

```text
/opt/docker-compose.d/headscale-server/certs
```

Caddy's actual certificate files normally appear under:

```text
/opt/docker-compose.d/headscale-server/certs/caddy/certificates
```

## Client Cannot Log In

Check:

- The client uses `https://hs.example.com`, not `http://`.
- The domain certificate is valid in a browser.
- Headscale is running.
- The client has been registered or has a valid preauth key.

Commands:

```bash
cd /opt/docker-compose.d/headscale-server
docker compose ps
docker compose logs --tail=120 headscale
docker compose exec headscale headscale users list
docker compose exec headscale headscale nodes list
```

## DERP Does Not Work

The embedded DERP uses:

- HTTPS on TCP `443`
- STUN on UDP `3478`

Check UDP `3478` in the cloud security group and host firewall. Then verify from a connected desktop client:

```bash
tailscale debug derp-map
tailscale debug derp headscale
```

## Only Self-Hosted DERP Is a Single Point of Failure

By default, the installer sets:

```yaml
derp:
  urls: []
```

That means only your embedded DERP is published. If the server is down, clients do not have another DERP relay. Install with `--include-official-derp` if you want official DERP regions as fallback.

## Back Up Before Changes

```bash
cd /opt/docker-compose.d/headscale-server
./scripts/backup.sh
```

Backups are written to:

```text
/opt/docker-compose.d/headscale-server/backups
```
