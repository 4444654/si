# Caddy VPS 中文管理菜单

在 Linux VPS 上安装 Caddy，并通过 SSH 中文菜单管理反向代理。无需 Docker。

## 功能

- 一键安装 Caddy，并添加第一个反向代理。
- 输入后端端口即可反代，例如 `5700` 等同于 `http://127.0.0.1:5700`。
- 多域名管理；支持添加、修改和删除站点。
- 自动 HTTPS，证书由 Caddy 自动申请和续签。
- 支持 HTTP / HTTPS 后端，以及纯 HTTP 的自定义监听端口。
- 查看服务状态、日志、端口占用和后端连接情况。
- 修改前自动备份；配置校验或重载失败时恢复原配置。
- 通过系统软件包管理器更新 Caddy。

这是 **SSH 终端中文菜单**，使用 systemd 服务在后台运行。关闭 SSH 后 Caddy 仍会运行。

## 一键下载安装：公开仓库

下面的命令用于**公开仓库**。如果仓库仍为私有，未认证下载通常会返回 404，请使用后面的私有仓库方法。

用 root 登录 VPS，复制整行执行：

```bash
curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 https://raw.githubusercontent.com/4444654/si/main/caddy_vps_cn.sh -o /root/caddy_vps_cn.sh && bash /root/caddy_vps_cn.sh
```

菜单中选 **1. 一键安装 + 添加反向代理**，按提示输入域名、后端端口和 HTTPS/HTTP 方式。

后续再次打开菜单：

```bash
caddy-menu
```

如果下载时提示 `curl: command not found`，Debian / Ubuntu 先执行 `apt-get update && apt-get install -y curl`；dnf 系统先执行 `dnf install -y curl`。

## 私有仓库下载安装

仓库为私有时，需要能读取 `4444654/si` 的 GitHub 访问令牌。

可以创建 Fine-grained personal access token：资源所有者选 `4444654`，仓库只选 `si`，给 **Contents: Read-only** 权限。创建方法见 [GitHub 官方说明](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)。

用 root 在 VPS 的 Bash 终端粘贴下面整段。出现提示时输入令牌；输入内容不会显示，也不会作为 curl 的命令行参数或写入文件。

```bash
caddy_repo_install() {
    local caddy_repo_token caddy_repo_result
    if (( EUID != 0 )); then
        printf '请先用 root 登录 VPS。\n' >&2
        return 1
    fi
    read -r -s -p '请输入 GitHub 访问令牌：' caddy_repo_token || return 1
    printf '\n'
    if [[ ! "$caddy_repo_token" =~ ^[A-Za-z0-9_]+$ ]]; then
        unset caddy_repo_token
        printf '令牌格式不正确。\n' >&2
        return 1
    fi
    printf 'header = "Authorization: Bearer %s"\nheader = "Accept: application/vnd.github.raw+json"\n' "$caddy_repo_token" |
        curl --config - --proto '=https' --tlsv1.2 -fsSL --retry 3 --connect-timeout 15 --max-time 120 'https://api.github.com/repos/4444654/si/contents/caddy_vps_cn.sh?ref=main' -o /root/caddy_vps_cn.sh
    caddy_repo_result=$?
    unset caddy_repo_token
    (( caddy_repo_result == 0 )) || return "$caddy_repo_result"
    bash /root/caddy_vps_cn.sh
}
caddy_repo_install
unset -f caddy_repo_install
```

请在普通终端中运行，避免开启会记录变量内容的 `set -x` 调试模式。无需把令牌发给别人。

也可以直接从已登录的 GitHub 页面下载脚本，上传到 VPS 的 `/root/`，然后运行：

```bash
bash /root/caddy_vps_cn.sh
```

如果希望免令牌下载，可以自行将仓库改为公开：仓库 **Settings → General → Danger Zone → Change repository visibility**，按页面提示选择 Public。公开后仓库代码可被所有人访问。步骤见 [GitHub 官方说明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility)。

## 使用前准备

1. 需要使用 Bash 4+、systemd 的 Linux VPS，以及 root / sudo 权限。
2. 自动安装支持 Debian / Ubuntu，以及有 dnf 的 Fedora / RHEL / Rocky / AlmaLinux 等发行版；需要能够访问官方软件源。
3. 先启动你的业务程序，例如监听 `127.0.0.1:5700`。脚本负责安装 Caddy 和配置反代，不安装业务程序。
4. 使用自动 HTTPS 时，域名 A / AAAA 记录应正确指向 VPS，云平台安全组与系统防火墙放行 **TCP 80、443**；UDP 443 用于 HTTP/3，可选。
5. 80 / 443 不能被 Nginx、Apache 或其他程序占用。菜单会提示占用情况。
6. 不支持泛域名证书；泛域名需要另外配置 DNS 插件。

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

## 验证范围

脚本已通过 Bash 语法检查、ShellCheck，以及 64 项本地验证，包括真实 Caddy 配置校验、多域名 HTTP 转发、中文终端输入、无效配置回退、重载失败回退及中断恢复。没有在所有发行版 VPS 上实际执行软件包安装，也没有通过本地测试申请公网证书。

## 官方参考

- [Caddy 安装](https://caddyserver.com/docs/install)
- [Caddy 自动 HTTPS](https://caddyserver.com/docs/automatic-https)
- [Caddy reverse_proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)
