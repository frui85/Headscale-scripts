# Headscale 新手完整使用文档

本文面向第一次部署 Headscale 的用户，按从零开始的顺序说明：

- 服务器需要准备什么
- 如何一键安装
- 如何生成客户端接入密钥
- Windows、macOS、Linux、Android、iOS 如何接入
- 如何验证 DERP 是否走自建中继
- 如何备份、升级、卸载
- HTTPS 证书如何申请和续期
- 是否需要增加计划任务

示例域名统一使用：

```text
hs.example.com
```

实际使用时请替换成你自己的域名。

## 一、部署前准备

### 1. 准备服务器

建议准备一台有公网 IP 的 Linux 服务器，例如 Debian、Ubuntu、CentOS、Rocky Linux、AlmaLinux。

最低要求：

- 1 核 CPU
- 512 MB 内存以上
- 5 GB 磁盘以上
- 一个公网 IPv4 或 IPv6
- 可以开放 TCP `80`、TCP `443`、UDP `3478`

### 2. 准备域名解析

在 DNS 服务商处添加解析：

```text
A     hs.example.com -> 服务器公网 IPv4
AAAA  hs.example.com -> 服务器公网 IPv6
```

如果服务器没有 IPv6，只配置 `A` 记录即可。

验证解析：

```bash
nslookup hs.example.com
```

确认返回的是你的服务器公网 IP。

### 3. 放行防火墙和安全组

必须放行：

| 协议 | 端口 | 用途 |
| --- | --- | --- |
| TCP | `80` | Caddy 自动申请证书时的 HTTP 验证，以及 HTTP 到 HTTPS 跳转 |
| TCP | `443` | Headscale HTTPS 入口和 DERP relay 流量 |
| UDP | `3478` | embedded DERP 的 STUN |

如果使用云服务器，需要同时检查：

- 云厂商安全组
- 系统防火墙，例如 `ufw`、`firewalld`、`iptables`
- 是否已有其他服务占用 `80` 或 `443`

## 二、一键安装

在服务器上执行：

```bash
curl -fsSL https://raw.githubusercontent.com/frui85/Headscale-scripts/main/install.sh \
  | sudo bash -s -- --domain hs.example.com --email admin@example.com --user default
```

参数含义：

| 参数 | 示例 | 说明 |
| --- | --- | --- |
| `--domain` | `hs.example.com` | Headscale 公网访问域名，必填 |
| `--email` | `admin@example.com` | Caddy/ACME 证书联系邮箱，建议填写真实邮箱 |
| `--user` | `default` | 初始 Headscale 用户名 |

安装完成后，默认目录为：

```text
/opt/docker-compose.d/headscale-server
```

安装器会生成：

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

其中：

- `data/` 保存 Headscale 数据库和私钥
- `certs/` 保存 Caddy 自动申请的 HTTPS 证书数据
- `client-connect.txt` 保存安装后生成的客户端接入说明和初始 auth key

## 三、安装后检查

进入安装目录：

```bash
cd /opt/docker-compose.d/headscale-server
```

查看容器状态：

```bash
docker compose ps
```

运行健康检查：

```bash
./scripts/healthcheck.sh
```

查看日志：

```bash
docker compose logs -f headscale
docker compose logs -f caddy
```

浏览器访问：

```text
https://hs.example.com
```

如果证书正常，浏览器不应该提示 HTTPS 证书错误。

## 四、重新安装并保留数据

如果已经安装过，可以直接重新执行一键安装命令：

```bash
curl -fsSL https://raw.githubusercontent.com/frui85/Headscale-scripts/main/install.sh \
  | sudo bash -s -- --domain hs.example.com --email admin@example.com --user default
```

默认会保留：

- `data/`：Headscale 数据库和私钥
- `certs/`：Caddy 证书和 ACME 账号数据
- `backups/`：历史备份

重新安装会刷新：

- `docker-compose.yml`
- `Caddyfile`
- `config/config.yaml`
- `config/derp.yaml`
- `config/acl.hujson`
- `scripts/`

如果你从 `/opt/docker-compose.d/headscale-server` 目录里直接运行安装脚本，安装器会自动改为从 GitHub 下载最新模板，避免把安装目录里的文件复制到自身。

## 五、生成客户端接入密钥

安装脚本会自动创建一个初始可复用 auth key，并写入：

```text
/opt/docker-compose.d/headscale-server/client-connect.txt
```

后续需要新增设备时，可以手动生成：

```bash
cd /opt/docker-compose.d/headscale-server
./scripts/genkey.sh --user default --expiration 24h
```

输出示例：

```text
f3e9b4e5032c4f119794710352e7c41846261ae774fd727d
```

这个值就是 `<AUTH_KEY>`。

生成单次使用密钥：

```bash
./scripts/genkey.sh --user default --expiration 24h --single-use
```

给另一个用户生成密钥：

```bash
./scripts/genkey.sh --user alice --expiration 24h
```

如果用户不存在，脚本会自动创建用户。

## 六、各客户端如何接入

所有客户端都只填写 Headscale 地址：

```text
https://hs.example.com
```

不要手动填写 DERP 地址。DERP map 由 Headscale 自动下发。

### Linux

安装 Tailscale 客户端后执行：

```bash
sudo tailscale up --login-server https://hs.example.com --authkey <AUTH_KEY>
```

查看状态：

```bash
tailscale status
```

验证 DERP map：

```bash
tailscale debug derp-map
```

### Windows

安装 Windows 版 Tailscale 后，打开 PowerShell：

```powershell
tailscale login --login-server https://hs.example.com
```

浏览器会打开登录/授权页面，按提示完成。

如果希望 Windows 机器无人登录桌面时也保持在线，在 Tailscale 托盘设置里开启 unattended mode。

### macOS

CLI 方式：

```bash
tailscale login --login-server=https://hs.example.com
```

图形界面方式：

1. 打开 Tailscale App
2. 添加账号
3. 选择自定义控制服务器
4. 填写 `https://hs.example.com`

### Android

在 Android Tailscale App 中：

```text
Accounts -> three-dot menu -> Use an alternate server -> https://hs.example.com
```

如果使用 auth key：

1. 先设置 alternate server
2. 再在账户菜单里选择 auth key 方式
3. 粘贴服务器生成的 `<AUTH_KEY>`

### iOS

在 iOS Tailscale App 中添加账号时：

1. 选择自定义控制服务器
2. 填写 `https://hs.example.com`
3. 按提示完成登录或授权

不同版本的 iOS App 菜单名称可能略有变化，核心要求是先选择自定义控制服务器。

## 七、验证自建 DERP 是否生效

在已经接入的桌面客户端上执行：

```bash
tailscale debug derp-map
```

预期能看到：

```text
headscale
Headscale Embedded DERP
```

继续测试 embedded DERP：

```bash
tailscale debug derp headscale
```

如果你安装时没有加 `--include-official-derp`，默认 DERP map 里只有自建 embedded DERP。这样更可控，但这台服务器也是 DERP 单点。

## 八、服务端常用管理命令

进入安装目录：

```bash
cd /opt/docker-compose.d/headscale-server
```

查看服务：

```bash
docker compose ps
```

重启：

```bash
docker compose restart
```

停止：

```bash
docker compose down
```

启动：

```bash
docker compose up -d
```

查看用户：

```bash
./scripts/manage.sh user list
```

查看节点：

```bash
./scripts/manage.sh node list
```

删除节点：

```bash
./scripts/manage.sh node delete --id <NODE_ID>
```

## 九、用户和节点增删改查

所有命令都在安装目录执行：

```bash
cd /opt/docker-compose.d/headscale-server
```

### 用户查询

```bash
./scripts/manage.sh user list
```

输出 JSON：

```bash
./scripts/manage.sh --output json user list
```

### 用户新增

```bash
./scripts/manage.sh user create fr-mbp
```

### 用户改名

按用户名改：

```bash
./scripts/manage.sh user rename --name fr-mbp fr-macbook
```

按用户 ID 改：

```bash
./scripts/manage.sh user rename --id 2 fr-macbook
```

### 用户删除

删除用户前，该用户下面不能有节点。先查节点：

```bash
./scripts/manage.sh node list
```

删除用户：

```bash
./scripts/manage.sh user delete --name fr-macbook
```

跳过确认：

```bash
./scripts/manage.sh user delete --name fr-macbook --force
```

### 节点查询

```bash
./scripts/manage.sh node list
```

只看某个用户：

```bash
./scripts/manage.sh node list --user fr-mbp
```

### 节点注册

当客户端登录后给出 register key，可以执行：

```bash
./scripts/manage.sh node register --key <REGISTER_KEY> --user fr-mbp
```

更推荐日常使用 auth key 接入：

```bash
./scripts/genkey.sh --user fr-mbp --expiration 24h
```

### 节点改名

```bash
./scripts/manage.sh node rename --id 2 fr-mbp
```

### 节点移动到另一个用户

```bash
./scripts/manage.sh node move --id 2 --user default
```

这里 `--user` 可以填用户名，脚本会自动解析为 Headscale 需要的用户 ID。

### 节点过期

过期会保留节点记录，但强制客户端重新认证：

```bash
./scripts/manage.sh node expire --id 2
```

指定过期时间：

```bash
./scripts/manage.sh node expire --id 2 --expiry 2026-06-01T00:00:00Z
```

### 节点删除

```bash
./scripts/manage.sh node delete --id 2
```

跳过确认：

```bash
./scripts/manage.sh node delete --id 2 --force
```

## 十、备份

手动备份：

```bash
cd /opt/docker-compose.d/headscale-server
./scripts/backup.sh
```

备份文件默认保存在：

```text
/opt/docker-compose.d/headscale-server/backups
```

备份内容包括：

- `.env`
- `Caddyfile`
- `docker-compose.yml`
- `config/`
- `data/`
- `certs/`
- `caddy_config/`
- `client-connect.txt`

建议在升级前先备份。

## 十一、升级

升级前先备份：

```bash
cd /opt/docker-compose.d/headscale-server
./scripts/backup.sh
```

使用仓库提供的升级脚本：

```bash
sudo bash update.sh --headscale-version 0.27.1
```

升级脚本会：

1. 默认先执行备份
2. 更新 `.env` 里的 `HEADSCALE_VERSION`
3. 拉取新镜像
4. 重新启动 Compose 服务
5. 执行健康检查

如果只想拉取当前 `.env` 中配置的版本：

```bash
sudo bash update.sh
```

如果确认不需要备份：

```bash
sudo bash update.sh --skip-backup
```

## 十二、卸载

停止服务但保留数据：

```bash
sudo bash uninstall.sh
```

这会执行 `docker compose down`，但不会删除：

- 配置
- 数据库
- 证书
- 备份

彻底删除：

```bash
sudo bash uninstall.sh --purge
```

`--purge` 会删除整个安装目录：

```text
/opt/docker-compose.d/headscale-server
```

执行前请确认已经备份。

## 十三、证书申请和续期

本项目使用 Caddy 自动管理 HTTPS 证书。

安装时传入：

```bash
--domain hs.example.com --email admin@example.com
```

安装器会生成 Caddy 配置。Caddy 启动后会自动：

1. 检查域名是否可公开访问
2. 通过 ACME 申请 HTTPS 证书
3. 将 HTTP 自动跳转到 HTTPS
4. 将证书和账号数据保存到 `./certs`
5. 在证书需要续期时自动续期

证书数据目录：

```text
/opt/docker-compose.d/headscale-server/certs
```

Caddy 实际证书文件通常位于：

```text
/opt/docker-compose.d/headscale-server/certs/caddy/certificates
```

查看证书文件：

```bash
find /opt/docker-compose.d/headscale-server/certs/caddy/certificates -type f
```

查看证书有效期：

```bash
find /opt/docker-compose.d/headscale-server/certs/caddy/certificates \
  -name '*.crt' \
  -exec openssl x509 -noout -subject -issuer -dates -in {} \;
```

### 证书有效期是多少

Let's Encrypt 目前仍以 90 天证书为常见默认周期，但官方已经宣布会逐步缩短默认周期，先到 64 天，再到 45 天。自动化续期会变得更重要。

你不需要在脚本里写死续期日期。Caddy 会根据证书状态自动处理续期。

### 是否需要加计划任务自动续期

不需要。

不要再额外配置 `certbot renew` 或类似 cron 任务，因为本项目没有使用 certbot，证书由 Caddy 管理。额外的续期工具可能会和 Caddy 的证书存储冲突。

只要满足下面条件，Caddy 会自动续期：

- Caddy 容器持续运行
- `certs/` 目录持久化，没有被删除
- 域名仍然解析到当前服务器
- TCP `80` 或 `443` 仍然从公网可访问
- 没有频繁重启或反复清空 Caddy 数据目录

### 可以加什么计划任务

可以加“监控提醒”计划任务，但不是续期任务。

例如每天检查一次证书到期时间：

```bash
sudo crontab -e
```

加入：

```cron
30 3 * * * find /opt/docker-compose.d/headscale-server/certs/caddy/certificates -name '*.crt' -exec openssl x509 -checkend 1209600 -noout -in {} \; >/dev/null || echo "Headscale certificate expires within 14 days" | logger -t headscale-cert
```

这个任务只做提醒，不会申请证书。

## 十四、常见问题

### 客户端应该填 DERP 域名吗

不需要。

客户端只填：

```text
https://hs.example.com
```

Headscale 会把 embedded DERP 信息下发给客户端。

### 证书申请失败怎么办

先看 Caddy 日志：

```bash
cd /opt/docker-compose.d/headscale-server
docker compose logs -f caddy
```

重点检查：

- DNS 是否指向当前服务器
- TCP `80` 和 `443` 是否公网可访问
- 服务器时间是否准确
- `certs/` 是否可写
- 是否触发了 ACME 频率限制

### DERP 不通怎么办

检查 UDP `3478`：

```bash
cd /opt/docker-compose.d/headscale-server
docker compose logs --tail=120 headscale
```

同时确认云安全组和系统防火墙都放行 UDP `3478`。

### auth key 生成失败怎么办

确认 Headscale 容器已经启动：

```bash
cd /opt/docker-compose.d/headscale-server
docker compose ps
```

再执行：

```bash
./scripts/genkey.sh --user default --expiration 24h
```

当前脚本会自动把用户名解析为 Headscale 需要的数字用户 ID。

## 参考资料

- Caddy Automatic HTTPS: <https://caddyserver.com/docs/automatic-https>
- Let's Encrypt certificate lifetime update: <https://letsencrypt.org/2026/02/24/rate-limits-45-day-certs.html>
