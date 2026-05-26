# Headscale-scripts

[English](README.md)

Headscale + embedded DERP Docker Compose 一键安装脚本。

本仓库用于一键安装 Headscale 自建控制服务器，并启用 Headscale embedded DERP。客户端只需要连接 Headscale 域名，DERP map 由 Headscale 自动下发。

## 目录结构

```text
Headscale-scripts/
├── install.sh
├── uninstall.sh
├── update.sh
├── docker-compose.yml
├── .env.example
├── Caddyfile
├── README.md
├── README.zh-CN.md
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
    ├── CLIENTS.zh-CN.md
    ├── USER_GUIDE.zh-CN.md
    ├── TROUBLESHOOT.md
    ├── TROUBLESHOOT.zh-CN.md
    ├── ARCHITECTURE.md
    └── ARCHITECTURE.zh-CN.md
```

## 快速安装

安装前先确认：

- 域名已经解析到服务器，例如 `hs.example.com`
- TCP `80` 和 `443` 已放行
- UDP `3478` 已放行

执行：

```bash
curl -fsSL https://raw.githubusercontent.com/frui85/Headscale-scripts/main/install.sh \
  | sudo bash -s -- --domain hs.example.com --email admin@example.com --user default
```

默认安装目录：

```text
/opt/docker-compose.d/headscale-server
```

Caddy 会根据 `--domain` 传入的域名自动申请 HTTPS 证书。证书数据挂载在：

```text
/opt/docker-compose.d/headscale-server/certs
```

## 本地安装

```bash
git clone https://github.com/frui85/Headscale-scripts.git
cd Headscale-scripts
sudo bash install.sh --domain hs.example.com --email admin@example.com --user default
```

如果已经安装过，可以直接重新执行安装命令。默认会保留安装目录下的 `data/`、`certs/`、`backups/`，只刷新 Compose、Caddy、Headscale 配置和辅助脚本。

常用参数：

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

如果希望保留 Tailscale 官方 DERP 网络作为兜底，安装时加 `--include-official-derp`。默认只发布 embedded DERP 区域。

## 服务管理

```bash
cd /opt/docker-compose.d/headscale-server
docker compose ps
docker compose logs -f headscale
docker compose logs -f caddy
./scripts/healthcheck.sh
./scripts/genkey.sh --user default
./scripts/backup.sh
```

更新：

```bash
sudo bash update.sh --headscale-version 0.27.1
```

卸载但保留数据：

```bash
sudo bash uninstall.sh
```

卸载并删除配置、数据、证书和备份：

```bash
sudo bash uninstall.sh --purge
```

## 客户端连接

客户端使用 Headscale URL，不要填写 DERP URL：

```text
https://hs.example.com
```

Linux：

```bash
sudo tailscale up --login-server https://hs.example.com --authkey <AUTH_KEY>
```

Windows：

```powershell
tailscale login --login-server https://hs.example.com
```

macOS：

```bash
tailscale login --login-server=https://hs.example.com
```

Android 和 iOS：添加自定义或备用控制服务器，填写 `https://hs.example.com`。

## DERP 域名

默认不需要单独的 DERP 域名。

默认部署用同一个域名同时承载 Headscale 和 embedded DERP：

```text
https://hs.example.com
```

客户端登录这个 Headscale URL 后，Headscale 会下发包含 embedded `headscale` DERP 区域的 DERP map。单服务器安装只需要：

- TCP `443`：HTTPS 和 DERP relay 流量
- UDP `3478`：STUN
- `server_url` 设置为 `https://hs.example.com`
- `derp.server.enabled: true`

只有在独立部署 DERP、DERP 跑在另一台服务器、多区域 DERP，或刻意把控制面和中继流量拆开时，才需要单独 DERP 域名。

更多文档：

- [新手完整使用文档](docs/USER_GUIDE.zh-CN.md)
- [客户端连接指南](docs/CLIENTS.zh-CN.md)
- [故障排查](docs/TROUBLESHOOT.zh-CN.md)
- [架构说明](docs/ARCHITECTURE.zh-CN.md)
