# 架构说明

## 组件

```text
Internet clients
      |
      | HTTPS 443 / STUN UDP 3478
      v
Public server
      |
      +-- caddy
      |     - 监听 TCP 80 和 443
      |     - 自动申请 HTTPS 证书
      |     - 将证书数据保存在 ./certs
      |     - 将 HTTPS 请求反向代理到 headscale:8080
      |
      +-- headscale
            - 在 Docker 内监听 8080
            - 将 SQLite 状态保存在 ./data
            - 通过 UDP 3478 暴露 embedded DERP/STUN
            - 向客户端下发 DERP map
```

## 安装目录

默认目录：

```text
/opt/docker-compose.d/headscale-server
```

运行时目录结构：

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

## 证书流程

安装器会写入 `.env`：

```env
DOMAIN=hs.example.com
ACME_EMAIL=admin@example.com
```

Caddy 通过 Docker Compose 读取这些变量。它监听 TCP `80` 和 `443`，完成 ACME 验证，并把证书数据写入挂载的 `./certs` 目录。

## DERP 流程

客户端不会连接单独的 DERP 配置端点。客户端先连接 Headscale：

```text
client -> https://hs.example.com -> caddy -> headscale
```

Headscale 返回 DERP map。默认配置启用 embedded DERP：

```yaml
derp:
  server:
    enabled: true
    stun_listen_addr: "0.0.0.0:3478"
  urls: []
```

在这个默认配置下，Headscale embedded DERP 是唯一 DERP 区域。安装时传入 `--include-official-derp` 会把 Tailscale 官方 DERP map 作为兜底。

## DERP 域名

默认架构不需要专用 DERP 域名。

同一个域名承担两个角色：

```text
https://hs.example.com
```

这个域名通过 TCP `443` 到达 Caddy，Caddy 把 Headscale 控制面流量代理到 `headscale:8080`，Headscale 再把 embedded DERP 区域发布到 DERP map。STUN 使用同一台公网服务器上的 UDP `3478`。

只有 DERP 没有 embedded 在当前 Headscale 实例里时，才需要单独 DERP 域名。常见场景：

- DERP 跑在另一台服务器
- 部署多个 DERP 区域
- 使用独立 `derper`，而不是 Headscale embedded DERP
- 想把 Headscale 控制面流量和中继流量隔离

## 持久化

持久化状态都在安装目录内：

- `data/`：Headscale SQLite 数据库和私钥
- `certs/`：Caddy 证书数据
- `caddy_config/`：Caddy 内部配置状态
- `config/`：Headscale 配置、DERP map 文件、ACL 文件
- `backups/`：`scripts/backup.sh` 生成的 tarball 备份
