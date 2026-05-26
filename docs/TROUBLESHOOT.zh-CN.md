# 故障排查

## 检查服务健康状态

在服务器上执行：

```bash
cd /opt/docker-compose.d/headscale-server
./scripts/healthcheck.sh
```

查看日志：

```bash
docker compose logs -f headscale
docker compose logs -f caddy
```

## Caddy 无法签发证书

先检查：

- `A` 或 `AAAA` 记录是否指向这台服务器
- 云厂商安全组是否放行 TCP `80` 和 `443`
- 服务器本机防火墙是否放行 TCP `80` 和 `443`
- 是否有其他进程占用了 `80` 或 `443`

证书数据目录：

```text
/opt/docker-compose.d/headscale-server/certs
```

Caddy 实际证书文件通常在：

```text
/opt/docker-compose.d/headscale-server/certs/caddy/certificates
```

## 客户端无法登录

检查：

- 客户端使用的是 `https://hs.example.com`，不是 `http://`
- 浏览器访问域名时证书有效
- Headscale 服务正在运行
- 客户端已经注册，或使用了有效的 preauth key

常用命令：

```bash
cd /opt/docker-compose.d/headscale-server
docker compose ps
docker compose logs --tail=120 headscale
docker compose exec headscale headscale users list
docker compose exec headscale headscale nodes list
```

## DERP 不工作

embedded DERP 使用：

- TCP `443` 上的 HTTPS
- UDP `3478` 上的 STUN

检查云厂商安全组和服务器本机防火墙是否放行 UDP `3478`。然后在已连接的桌面客户端上验证：

```bash
tailscale debug derp-map
tailscale debug derp headscale
```

## 只使用自建 DERP 是单点

默认安装配置为：

```yaml
derp:
  urls: []
```

这表示只发布你的 embedded DERP。如果这台服务器不可用，客户端没有其他 DERP relay 可用。需要兜底时，安装时加 `--include-official-derp`，保留官方 DERP 区域。

## 变更前备份

```bash
cd /opt/docker-compose.d/headscale-server
./scripts/backup.sh
```

备份文件会写入：

```text
/opt/docker-compose.d/headscale-server/backups
```
