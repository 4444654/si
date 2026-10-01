# Caddy VPS 中文管理菜单

Caddy VPS 中文管理菜单 v2.0.1：在 Linux VPS 上安装、修复和管理 Caddy，并通过 SSH 中文菜单管理反向代理。无需 Docker。

## 功能

- 一键安装 Caddy，并添加第一个反向代理。
- 输入后端端口即可反代，例如 `5700` 等同于 `http://127.0.0.1:5700`。
- 多域名管理；支持添加、修改和删除站点。
- 自动 HTTPS，证书由 Caddy 自动申请和续签。
- 支持 HTTP / HTTPS 后端，以及纯 HTTP 的自定义监听端口。
- 查看服务状态、日志、端口占用和后端连接情况。
- 修改前自动备份；配置校验或重载失败时恢复原配置。
- 自动识别 Debian / Ubuntu，并支持常见 dnf 系发行版。
- 自动刷新 Caddy GPG Key；软件源安装失败时提供官方 Release 备用安装方式。
- 新增 Caddy 修复工具，可处理 GPG、软件源、配置与 systemd 服务问题。
- 通过系统软件包管理器更新 Caddy。

这是 **SSH 终端中文菜单**，使用 systemd 服务在后台运行。关闭 SSH 后 Caddy 仍会运行。

## 一键下载安装

用 root 登录 VPS，复制整行执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/4444654/si/main/caddy_vps_cn.sh)
```

菜单中选 **1. 一键安装 + 添加反向代理**，按提示输入域名、后端端口和 HTTPS/HTTP 方式。

后续再次打开菜单：

```bash
fd
```

如果下载时提示 `curl: command not found`，Debian / Ubuntu 先执行 `apt-get update && apt-get install -y curl`；dnf 系统先执行 `dnf install -y curl`。

## 使用前准备

1. 需要使用 Bash 4+、systemd 的 Linux VPS，以及 root / sudo 权限。
2. v2.0.1 会通过 `/etc/os-release` 自动识别 Debian / Ubuntu；同时支持 Fedora / RHEL / Rocky / AlmaLinux 等带 dnf 的发行版。需要 systemd、Bash 4+ 和 root 权限。
3. Debian / Ubuntu 安装会刷新 Caddy 官方仓库 GPG Key；若仓库签名或安装失败，会尝试 Caddy 官方 GitHub Release `.deb` 备用安装方式。
4. 先启动你的业务程序，例如监听 `127.0.0.1:5700`。脚本负责安装 Caddy 和配置反代，不安装业务程序。
5. 使用自动 HTTPS 时，域名 A / AAAA 记录应正确指向 VPS，云平台安全组与系统防火墙放行 **TCP 80、443**；UDP 443 用于 HTTP/3，可选。
6. 80 / 443 不能被 Nginx、Apache 或其他程序占用。菜单会提示占用情况。
7. 不支持泛域名证书；泛域名需要另外配置 DNS 插件。

示例：

| 要填写的项目 | 示例 |
| --- | --- |
| 访问域名 | `app.example.com` |
| 后端端口 | `5700` |
| 等效后端地址 | `http://127.0.0.1:5700` |
| 访问方式 | 自动 HTTPS |
| 配置完成后的访问地址 | `https://app.example.com` |

后端也支持 `10.0.0.2:8080`、`https://backend.example.com:443` 和 `http://[::1]:8080`。不支持后端 URL 中的账号密码、路径或查询参数；访问者的请求路径与参数会原样转发。HTTPS 后端证书必须有效，脚本不会跳过证书校验。

配置已加载不代表证书已签发。首次申请证书时可通过菜单查看 Caddy 运行日志。

## 文件位置

| 内容 | 路径 |
| --- | --- |
| 主配置 | `/etc/caddy/Caddyfile` |
| 本菜单管理的站点 | `/etc/caddy/vps-panel-sites/*.caddy` |
| 配置备份 | `/var/backups/caddy-vps-panel/*.tar.gz` |
| 快捷命令 | `/usr/local/bin/caddy-menu` |
| Caddy 证书与状态数据 | `/var/lib/caddy` |

已有标准 Caddyfile 会保留并追加菜单站点的 import。自定义服务路径、caddy-api 服务或其他面板管理的实例，需要单独处理。

防火墙菜单只修改已启用的 UFW / firewalld；云平台安全组要在服务商控制台设置。

## v2.0.1 检查

发布时检查 GitHub Raw 可下载、Bash 语法、安装流程关键分支与菜单入口。实际软件包安装、不同云厂商网络环境和公网证书签发仍取决于目标 VPS 环境。

## 官方参考

- [Caddy 安装](https://caddyserver.com/docs/install)
- [Caddy 自动 HTTPS](https://caddyserver.com/docs/automatic-https)
- [Caddy reverse_proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)
