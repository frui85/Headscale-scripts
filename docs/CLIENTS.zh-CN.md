# 客户端连接指南

客户端连接的是 Headscale 控制服务器 URL。不要在客户端里单独配置 DERP URL。

## 服务器地址

把示例域名替换成你的真实域名：

```text
https://hs.example.com
```

客户端连接后，Headscale 会下发 DERP map。默认安装配置下，这个 DERP map 包含 Headscale embedded DERP 区域。

## 默认不需要单独 DERP 域名

安装器默认使用同一个域名承载 Headscale 和 embedded DERP。客户端不应该手动填写 DERP 域名或 DERP URL。

使用：

```text
https://hs.example.com
```

不要使用：

```text
https://derp.hs.example.com
```

只有 DERP 不在这台 Headscale 服务器上运行时，才需要单独 DERP 域名。

## 生成授权密钥

在服务器上执行：

```bash
cd /opt/docker-compose.d/headscale-server
./scripts/genkey.sh --user default --expiration 24h
```

命令会输出一个 preauth key。Linux 和其他非交互式客户端可以用它接入。

## 生成客户端接入包

管理员或客服可以直接生成一份接入包发给用户：

```bash
cd /opt/docker-compose.d/headscale-server
./scripts/onboard.sh --user fr-mbp --expiration 24h
```

输出里会包含：

- Headscale 地址
- auth key
- Linux / Windows / macOS 命令
- Android / iOS 操作提示

客户端使用 auth key 后会自动加入服务端，不需要再手工执行 `nodes register`。

临时设备可以使用 ephemeral key：

```bash
./scripts/onboard.sh --user temp-iphone --ephemeral --expiration 2h
```

ephemeral 节点适合短期设备。客户端执行 `tailscale logout` 后，节点会更快从 tailnet 移除。

## Linux

```bash
sudo tailscale up --login-server https://hs.example.com --authkey <AUTH_KEY>
```

验证状态：

```bash
tailscale status
tailscale debug derp-map
```

## Windows

打开 PowerShell：

```powershell
tailscale login --login-server https://hs.example.com
```

按浏览器提示完成登录。如果机器需要在无人登录桌面时保持在线，在 Tailscale 托盘设置里开启 unattended mode。

## macOS

CLI：

```bash
tailscale login --login-server=https://hs.example.com
```

图形界面：打开 Tailscale，添加自定义控制服务器，填写 `https://hs.example.com`。

## Android

在 Tailscale App 中：

```text
Accounts -> three-dot menu -> Use an alternate server -> https://hs.example.com
```

如果使用 auth key，先设置 alternate server，再在账户菜单里选择 auth key 方式。

## iOS

在 Tailscale App 中添加账号时，选择自定义控制服务器并填写：

```text
https://hs.example.com
```

不同版本 App 的入口可能略有变化。关键是先选择自定义控制服务器，再完成登录。

## 验证 DERP

在已连接的桌面客户端上执行：

```bash
tailscale debug derp-map
tailscale debug derp headscale
```

预期结果：DERP map 中包含 `headscale` 区域或 `Headscale Embedded DERP`。

## 用户和节点管理

查看用户：

```bash
cd /opt/docker-compose.d/headscale-server
./scripts/manage.sh user list
```

查看节点：

```bash
./scripts/manage.sh node list
```

注册节点：

```bash
./scripts/manage.sh node register --key <REGISTER_KEY> --user default
```

删除节点：

```bash
./scripts/manage.sh node delete --id <NODE_ID>
```

清理已退出或过期的节点：

```bash
./scripts/cleanup.sh --expired --delete-empty-users
./scripts/cleanup.sh --apply --expired --delete-empty-users
```

第一条是 dry-run，只显示会删除什么；第二条才会真正删除。
