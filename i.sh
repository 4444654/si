#!/usr/bin/env bash
# Caddy VPS 中文菜单：短安装入口
set -euo pipefail
umask 077

if (( EUID != 0 )); then
    printf '请用 root 运行此安装命令。\n' >&2
    exit 1
fi

caddy_install_dir="$(mktemp -d /tmp/caddy-install-XXXXXX)"
trap 'rm -rf -- "$caddy_install_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf '正在下载 Caddy 中文管理菜单……\n'
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --connect-timeout 15 --max-time 120 \
    https://raw.githubusercontent.com/4444654/si/main/caddy_vps_cn.sh \
    -o "$caddy_install_dir/caddy_vps_cn.sh"

bash -n "$caddy_install_dir/caddy_vps_cn.sh"
bash "$caddy_install_dir/caddy_vps_cn.sh"
