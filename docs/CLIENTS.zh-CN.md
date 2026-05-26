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
