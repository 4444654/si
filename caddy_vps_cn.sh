#!/usr/bin/env bash
# Caddy VPS 中文管理菜单 v1.0.0
# 用途：在使用 systemd 的 Linux VPS 上安装 Caddy、管理多个 HTTP/HTTPS 反向代理。
# 软件源：Caddy 官方文档列出的稳定版仓库；不安装 Docker，不停止其他 Web 服务。
# 官方参考：https://caddyserver.com/docs/install
#           https://caddyserver.com/docs/automatic-https
#           https://caddyserver.com/docs/caddyfile/directives/reverse_proxy

set -uo pipefail
umask 077

VERSION="1.0.0"
CFG="/etc/caddy/Caddyfile"
SITES="/etc/caddy/vps-panel-sites"
BACKUPS="/var/backups/caddy-vps-panel"
IMPORT="import /etc/caddy/vps-panel-sites/*.caddy"
WORK=""
TX_PATH=""
TX_BACKUP=""
TX_HAD_OLD=0
TX_WAS_ACTIVE=0
TX_RELOAD_ATTEMPTED=0
LAST_BACKUP=""
OS_ID=""
OS_LIKE=""
OS_NAME=""
PKG_KIND=""
CADDY_BIN=""

say()  { printf '%s\n' "$*"; }
ok()   { printf '[成功] %s\n' "$*"; }
warn() { printf '[提示] %s\n' "$*"; }
err()  { printf '[失败] %s\n' "$*" >&2; }

ask() {
    local _ask_name="$1" _ask_prompt="$2" _ask_default="${3:-}" _ask_response
    printf '%s' "$_ask_prompt" >&3
    if [[ -n "$_ask_default" ]]; then printf ' [%s]' "$_ask_default" >&3; fi
    printf '：' >&3
    IFS= read -r -u 3 _ask_response || return 1
    printf -v "$_ask_name" '%s' "${_ask_response:-$_ask_default}"
}

confirm() {
    local reply
    ask reply "$1（输入 y 确认，直接回车取消）" || return 1
    [[ "$reply" == "y" || "$reply" == "Y" ]]
}

pause_menu() {
    printf '按回车返回菜单：' >&3
    IFS= read -r -u 3 || exit 0
}

usage() {
    cat <<'HELP'
Caddy VPS 中文管理菜单

运行：sudo bash caddy_vps_cn.sh
帮助：bash caddy_vps_cn.sh --help

这是 SSH 终端里的中文交互菜单。安装完成后也可运行：sudo caddy-menu
支持 Debian/Ubuntu，以及有 dnf 的 Fedora/RHEL/Rocky/AlmaLinux 等发行版。
要求：Linux、Bash 4+、systemd、root/sudo、能够访问官方软件源。

首次使用：
  1. 将脚本上传到 VPS，例如 /root/caddy_vps_cn.sh。
  2. 在 SSH 中执行：sudo bash /root/caddy_vps_cn.sh
  3. 选择“1. 一键安装 + 添加反向代理”。
  4. 输入域名（例如 app.example.com）。
  5. 输入后端端口（例如 5700），等同于 http://127.0.0.1:5700。
  6. 选择自动 HTTPS 或纯 HTTP，确认后应用。

后端还支持：127.0.0.1:8080、10.0.0.2:8080、http://host:8080、
https://backend.example.com:443、http://[::1]:8080。
不支持后端 URL 的路径、账号密码、查询参数或多个后端；路径与请求参数会原样转发。
HTTPS 后端支持默认 Host（使用后端域名）或保留访问者域名两种方式。

使用自动 HTTPS 前：
  - 域名 A/AAAA 记录应指向这台 VPS；不要留着错误的 AAAA 记录。
  - 云平台安全组和系统防火墙放行 TCP 80、443；UDP 443 用于 HTTP/3，可选。
  - 对应端口不能被 Nginx、Apache 或其他进程占用。
  - 后端服务必须已启动；脚本只配置反代，不安装你的业务程序。
  - 泛域名证书需要 DNS 插件，本脚本使用普通域名的自动 HTTPS。
  - 配置加载成功不等于证书已经签发；签发过程请查看 Caddy 日志。

配置路径：/etc/caddy/Caddyfile
本菜单站点：/etc/caddy/vps-panel-sites/*.caddy
自动备份：/var/backups/caddy-vps-panel/*.tar.gz（仅 root 可读）
证书数据由 Caddy 保存在 /var/lib/caddy；本脚本不会删除它。
已有标准 Caddyfile 会保留，并追加本菜单的 import。
自定义配置路径、caddy-api 服务或其他面板管理的实例，请单独处理。
防火墙菜单只修改已启用的 UFW / firewalld，不启用防火墙、不关闭 SSH。

备份恢复（备份包含当时的 /etc/caddy 全目录，不包含证书数据）：
  先另外备份现有 /etc/caddy，再将选定的可信备份解压到一个临时目录，
  按需恢复其中的文件；然后运行菜单“校验并重载”。不要直接混合覆盖多个备份。

软件源说明与参考：
https://caddyserver.com/docs/install
https://caddyserver.com/docs/automatic-https
HELP
}

valid_port() {
    [[ "$1" =~ ^[0-9]{1,5}$ ]] || return 1
    (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

valid_ipv4() {
    local input="$1" item
    local -a octets
    [[ "$input" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    IFS=. read -r -a octets <<< "$input"
    for item in "${octets[@]}"; do
        [[ "$item" =~ ^(0|[1-9][0-9]{0,2})$ ]] || return 1
        (( 10#$item <= 255 )) || return 1
    done
}

valid_ipv6() {
    local input="$1" item remainder count=0
    local -a groups
    [[ "$input" =~ ^[0-9a-fA-F:]+$ && "$input" == *:* ]] || return 1
    [[ "$input" != *:::* ]] || return 1
    remainder="${input/::/}"
    [[ "$remainder" != *::* ]] || return 1
    IFS=: read -r -a groups <<< "$input"
    for item in "${groups[@]}"; do
        [[ -z "$item" ]] && continue
        [[ "$item" =~ ^[0-9a-fA-F]{1,4}$ ]] || return 1
        (( count += 1 ))
    done
    if [[ "$input" == *::* ]]; then
        (( count < 8 ))
    else
        [[ "$input" != :* && "$input" != *: ]] && (( count == 8 ))
    fi
}

valid_hostname() {
    local input="$1" label
    local -a labels
    [[ ${#input} -le 253 && "$input" =~ ^[a-zA-Z0-9.-]+$ ]] || return 1
    [[ "$input" != .* && "$input" != *. && "$input" != *..* ]] || return 1
    # 数字点分地址必须是有效的 IPv4；域名允许内网单标签。
    if [[ "$input" =~ ^[0-9.]+$ ]]; then valid_ipv4 "$input"; return; fi
    IFS=. read -r -a labels <<< "$input"
    for label in "${labels[@]}"; do
        [[ ${#label} -le 63 && "$label" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] || return 1
    done
}

valid_public_domain() {
    valid_hostname "$1" || return 1
    [[ "$1" == *.* && ! "$1" =~ ^[0-9.]+$ ]] || return 1
    case "$1" in
        *.localhost|*.local|*.internal|*.test|*.invalid|*.example|*.onion) return 1 ;;
    esac
}

# 结果写入固定的全局变量，不使用 eval，也不把用户输入作为 shell 命令。
normalize_upstream() {
    local input="$1" scheme="http" host port
    if [[ "$input" =~ ^[0-9]{1,5}$ ]]; then
        valid_port "$input" || return 1
        UP_SCHEME="http"; UP_HOST="127.0.0.1"; UP_PORT="$((10#$input))"
        UPSTREAM="http://$UP_HOST:$UP_PORT"
        return 0
    fi
    case "$input" in
        http://*) input="${input#http://}" ;;
        https://*) scheme="https"; input="${input#https://}" ;;
        *://*) return 1 ;;
    esac
    input="${input%/}"
    [[ "$input" =~ ^(\[[0-9a-fA-F:]+\]|[a-zA-Z0-9.-]+)(:([0-9]{1,5}))?$ ]] || return 1
    host="${BASH_REMATCH[1]}"; port="${BASH_REMATCH[3]:-}"
    if [[ "$host" == \[*\] ]]; then
        valid_ipv6 "${host:1:-1}" || return 1
    else
        valid_hostname "$host" || return 1
        host="${host,,}"
    fi
    if [[ -z "$port" ]]; then
        if [[ "$scheme" == "https" ]]; then port=443; else port=80; fi
    fi
    valid_port "$port" || return 1
    UP_SCHEME="$scheme"; UP_HOST="$host"; UP_PORT="$((10#$port))"
    UPSTREAM="$UP_SCHEME://$UP_HOST:$UP_PORT"
}

download() {
    curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-delay 2 \
        --connect-timeout 15 --max-time 180 "$1" -o "$2"
}

check_service() {
    command -v caddy >/dev/null 2>&1 || { err "还没有安装 Caddy，请先选安装。"; return 1; }
    CADDY_BIN="$(command -v caddy)"
    [[ -x /usr/bin/caddy && "$(readlink -f "$CADDY_BIN")" == "$(readlink -f /usr/bin/caddy)" ]] || {
        err "Caddy 程序不在官方软件包的 /usr/bin/caddy 路径，请单独处理自定义安装。"; return 1;
    }
    [[ "$("$CADDY_BIN" version)" == v2.* ]] || { err "只支持 Caddy 2。"; return 1; }
    if systemctl is-active --quiet caddy-api; then
        err "检测到运行中的 caddy-api 服务，请先处理已有实例，避免配置冲突。"; return 1
    fi
    local start reload config_re='--config[[:space:]]+/etc/caddy/Caddyfile([[:space:];]|$)'
    start="$(systemctl show caddy -p ExecStart --value 2>/dev/null)" || return 1
    reload="$(systemctl show caddy -p ExecReload --value 2>/dev/null)" || return 1
    if [[ "$start" != *'path=/usr/bin/caddy '* || ! "$start" =~ $config_re || "$start" == *"--resume"* || ! "$reload" =~ $config_re ]]; then
        err "已有服务没有使用标准的 $CFG；本菜单不会覆盖自定义服务。"; return 1
    fi
    if ! id caddy >/dev/null 2>&1 || ! getent group caddy >/dev/null 2>&1; then
        err "缺少官方软件包创建的 caddy 用户/组。"; return 1
    fi
    [[ ! -L "$CFG" && ! -L "$SITES" ]] || {
        err "检测到配置路径是符号链接，请先改用普通文件/目录。"; return 1;
    }
}

make_backup() {
    [[ -d /etc/caddy ]] || return 0
    install -d -m 0700 "$BACKUPS" || return 1
    LAST_BACKUP="$(mktemp "$BACKUPS/config-$(date +%Y%m%d-%H%M%S)-XXXXXX.tar.gz")" || return 1
    if ! tar -czf "$LAST_BACKUP" -C /etc caddy; then
        rm -f -- "$LAST_BACKUP"; LAST_BACKUP=""
        err "备份失败，取消修改。"; return 1
    fi
    chmod 0600 "$LAST_BACKUP" || return 1
}

atomic_copy() {
    local source="$1" target="$2" attributes="${3:-target}" tmp reference=""
    [[ ! -L "$target" ]] || { err "拒绝替换符号链接：$target"; return 1; }
    tmp="$(mktemp "$(dirname "$target")/.caddy-panel-XXXXXX")" || return 1
    if ! cat -- "$source" > "$tmp"; then rm -f -- "$tmp"; return 1; fi
    if [[ "$attributes" == source ]]; then reference="$source"; elif [[ -e "$target" ]]; then reference="$target"; fi
    if [[ -n "$reference" ]]; then
        if ! chown --reference="$reference" "$tmp" || ! chmod --reference="$reference" "$tmp"; then
            rm -f -- "$tmp"; return 1
        fi
    else
        if ! chown root:caddy "$tmp" || ! chmod 0640 "$tmp"; then
            rm -f -- "$tmp"; return 1
        fi
    fi
    if ! mv -f -- "$tmp" "$target"; then rm -f -- "$tmp"; return 1; fi
    if command -v restorecon >/dev/null 2>&1; then restorecon "$target" || return 1; fi
}

rollback_transaction() {
    [[ -n "$TX_PATH" ]] || return 0
    local restored=1
    if (( TX_HAD_OLD )); then
        atomic_copy "$TX_BACKUP" "$TX_PATH" source || restored=0
    else
        rm -f -- "$TX_PATH" || restored=0
    fi
    if (( ! restored )); then
        err "自动恢复文件失败，请使用备份恢复：$LAST_BACKUP"; return 1
    fi
    TX_PATH=""
    if (( TX_RELOAD_ATTEMPTED )); then
        if (( TX_WAS_ACTIVE )); then
            if systemctl is-active --quiet caddy; then
                systemctl reload caddy || { err "旧配置已恢复，但重载失败，请检查日志。"; return 1; }
            else
                systemctl start caddy || { err "旧配置已恢复，但服务启动失败，请检查日志。"; return 1; }
            fi
        elif systemctl is-active --quiet caddy; then
            systemctl stop caddy || return 1
        fi
    fi
    warn "已恢复修改前的配置。"
}

validate_config() {
    "$CADDY_BIN" validate --config "$CFG" --adapter caddyfile
}

activate_config() {
    systemctl enable caddy || return 1
    if systemctl is-active --quiet caddy; then
        systemctl reload caddy
    else
        systemctl start caddy
    fi
}

apply_file() {
    local target="$1" source="$2"
    [[ -z "$TX_PATH" ]] || { err "尚有未完成的配置事务，请退出并检查备份。"; return 1; }
    [[ ! -L "$target" ]] || { err "拒绝修改符号链接：$target"; return 1; }
    make_backup || return 1
    TX_HAD_OLD=0; TX_WAS_ACTIVE=0; TX_RELOAD_ATTEMPTED=0
    TX_BACKUP="$WORK/rollback-file"
    if [[ -e "$target" ]]; then
        cp -a -- "$target" "$TX_BACKUP" || return 1
        TX_HAD_OLD=1
    fi
    systemctl is-active --quiet caddy && TX_WAS_ACTIVE=1
    TX_PATH="$target"
    if [[ "$source" == "DELETE" ]]; then
        rm -f -- "$target" || { rollback_transaction; return 1; }
    else
        atomic_copy "$source" "$target" || { rollback_transaction; return 1; }
    fi
    if ! validate_config; then
        err "配置校验没有通过，取消应用。"
        rollback_transaction
        return 1
    fi
    TX_RELOAD_ATTEMPTED=1
    if ! activate_config; then
        err "服务未能加载新配置。"
        rollback_transaction
        journalctl -u caddy -n 25 --no-pager || true
        return 1
    fi
    TX_PATH=""
    ok "配置已加载；备份：$LAST_BACKUP"
}

ensure_layout() {
    local fresh="${1:-0}" candidate="$WORK/Caddyfile-new"
    check_service || return 1
    if [[ ! -d "$SITES" ]]; then
        install -d -m 0750 -o root -g caddy "$SITES" || return 1
    fi
    if command -v restorecon >/dev/null 2>&1; then restorecon -R "$SITES" || return 1; fi
    if [[ -f "$CFG" ]] && grep -Fxq "$IMPORT" "$CFG" && (( ! fresh )); then return 0; fi
    if [[ -f "$CFG" ]] && (( ! fresh )); then
        cp -- "$CFG" "$candidate" || return 1
        printf '\n# Caddy VPS 中文菜单：各站点独立保存\n%s\n' "$IMPORT" >> "$candidate" || return 1
    else
        printf '# Caddy VPS 中文菜单\n# 使用 caddy-menu 添加站点\n%s\n' "$IMPORT" > "$candidate" || return 1
    fi
    "$CADDY_BIN" fmt --overwrite "$candidate" || return 1
    apply_file "$CFG" "$candidate"
}

save_menu_command() {
    local source
    source="$(readlink -f -- "${BASH_SOURCE[0]}")" || return 0
    if [[ -f "$source" && "$source" != /usr/local/bin/caddy-menu ]]; then
        install -m 0755 "$source" /usr/local/bin/caddy-menu || {
            warn "快捷命令未写入，可继续用 bash 脚本原路径运行。"; return 0;
        }
    fi
}

install_caddy() {
    local had_config=0 had_binary=0 fresh=0
    [[ -e "$CFG" || -L "$CFG" ]] && had_config=1
    command -v caddy >/dev/null 2>&1 && had_binary=1
    if (( had_binary )); then
        say "检测到已有 Caddy，保留已有安装与配置。"
        ensure_layout || return 1
        validate_config && activate_config || return 1
        save_menu_command
        ok "Caddy 已就绪。以后运行：sudo caddy-menu"
        return 0
    fi
    say "正在从官方稳定版仓库安装 Caddy……"
    case "$PKG_KIND" in
        apt)
            apt-get update || return 1
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
                ca-certificates curl gnupg debian-keyring debian-archive-keyring \
                apt-transport-https iproute2 || return 1
            download 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' "$WORK/caddy-key.asc" || return 1
            gpg --batch --yes --dearmor -o "$WORK/caddy-key.gpg" "$WORK/caddy-key.asc" || return 1
            download 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' "$WORK/caddy-stable.list" || return 1
            install -m 0644 "$WORK/caddy-key.gpg" /usr/share/keyrings/caddy-stable-archive-keyring.gpg || return 1
            install -m 0644 "$WORK/caddy-stable.list" /etc/apt/sources.list.d/caddy-stable.list || return 1
            apt-get update || return 1
            DEBIAN_FRONTEND=noninteractive apt-get install -y caddy || return 1
            ;;
        dnf)
            local plugin_package="dnf-plugins-core"
            if dnf --version 2>/dev/null | head -1 | grep -Eq '^dnf5|^5\.'; then plugin_package="dnf5-plugins"; fi
            dnf install -y ca-certificates curl iproute "$plugin_package" || return 1
            dnf -y copr enable @caddy/caddy || return 1
            dnf install -y caddy || return 1
            ;;
        *) err "当前系统不支持自动安装，请使用 Debian/Ubuntu 或 dnf 系发行版。"; return 1 ;;
    esac
    systemctl daemon-reload || return 1
    # 只有安装前不存在配置时，才用菜单配置替换软件包附带的默认欢迎页。
    (( ! had_config && ! had_binary )) && fresh=1
    ensure_layout "$fresh" || return 1
    save_menu_command
    ok "安装完成，已设置开机自启。以后运行：sudo caddy-menu"
}

port_available_for_caddy() {
    local port="$1" line rows
    command -v ss >/dev/null 2>&1 || { err "缺少 ss，请安装 iproute2（Debian/Ubuntu）或 iproute（RHEL）。"; return 1; }
    rows="$(ss -H -ltnp "sport = :$port")" || return 1
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" != *'"caddy"'* ]]; then
            err "TCP $port 被其他程序占用：$line"
            warn "请自行处理占用，或使用纯 HTTP 的其他监听端口。"
            return 1
        fi
    done <<< "$rows"
}

render_site() {
    local domain="$1" mode="$2" listen_port="$3" upstream="$4" host_mode="$5" target="$6" address
    if [[ "$mode" == "https" ]]; then address="$domain"; else address="http://$domain:$listen_port"; fi
    {
        printf '# panel-domain: %s\n# panel-mode: %s\n# panel-port: %s\n# panel-upstream: %s\n# panel-host: %s\n' \
            "$domain" "$mode" "$listen_port" "$upstream" "$host_mode"
        printf '%s {\n    encode zstd gzip\n' "$address"
        if [[ "$upstream" == https://* ]]; then
            printf '    reverse_proxy %s {\n' "$upstream"
            if [[ "$host_mode" == "original" ]]; then
                printf '        header_up Host {hostport}\n'
            else
                printf '        header_up Host {upstream_hostport}\n'
            fi
            printf '    }\n'
        else
            printf '    reverse_proxy %s\n' "$upstream"
        fi
        printf '}\n'
    } > "$target"
}

add_proxy() {
    ensure_layout || return 1
    local domain raw mode_choice mode listen_port=443 host_choice host_mode="upstream" target candidate
    say ""; say "添加 / 修改反向代理"
    say "域名示例：app.example.com。普通 HTTPS 不支持泛域名，中文域名请使用 Punycode。"
    ask domain "请输入域名或 HTTP 用的 IPv4 地址（回车取消）" || return 1
    [[ -n "$domain" ]] || return 0
    domain="${domain,,}"
    valid_hostname "$domain" || { err "域名/地址格式错误；不要输入协议、端口或路径。"; return 1; }
    target="$SITES/$domain.caddy"
    if [[ -f "$target" ]]; then
        say "当前配置："; cat -- "$target"
        confirm "这个地址已有菜单配置，是否修改" || return 0
    fi
    ask raw "后端地址或端口，例如 5700 / 127.0.0.1:8080 / https://host:443" "5700" || return 1
    normalize_upstream "$raw" || { err "后端格式错误，只支持 HTTP/HTTPS 的主机和端口。"; return 1; }
    say "1. 自动 HTTPS（需要解析域名并放行 TCP 80、443）"
    say "2. 纯 HTTP（支持域名/IP，可自定义监听端口）"
    ask mode_choice "请选择访问方式" "1" || return 1
    case "$mode_choice" in
        1)
            mode="https"
            valid_public_domain "$domain" || { err "自动 HTTPS 请填写有效的公网域名。"; return 1; }
            port_available_for_caddy 80 && port_available_for_caddy 443 || return 1
            ;;
        2)
            mode="http"
            ask listen_port "HTTP 监听端口" "80" || return 1
            valid_port "$listen_port" || { err "端口必须为 1～65535。"; return 1; }
            listen_port="$((10#$listen_port))"
            [[ "$listen_port" != 2019 ]] || { err "2019 通常是 Caddy 本地管理端口，请换一个。"; return 1; }
            port_available_for_caddy "$listen_port" || return 1
            ;;
        *) err "请选择 1 或 2。"; return 1 ;;
    esac
    # 避免新手将本机反代指回 Caddy 自身。其他本机地址仍需用户自行核对。
    if [[ "$UP_HOST" == "127.0.0.1" || "$UP_HOST" == "localhost" || "$UP_HOST" == "[::1]" || "$UP_HOST" == "$domain" ]]; then
        if [[ "$UP_PORT" == "$listen_port" || ( "$mode" == "https" && "$UP_PORT" == 80 ) ]]; then
            err "后端地址指向当前监听端口，会造成循环或端口冲突，请填写业务程序端口。"; return 1
        fi
    fi
    if [[ "$UP_SCHEME" == "https" ]]; then
        say "HTTPS 后端的 Host：1. 使用后端域名（默认）；2. 保留访问者的域名"
        ask host_choice "请选择" "1" || return 1
        case "$host_choice" in 1) host_mode="upstream" ;; 2) host_mode="original" ;; *) err "请选择 1 或 2。"; return 1 ;; esac
        warn "会验证后端证书。HTTPS 后端证书必须匹配后端域名；不跳过证书校验。"
    fi
    local address
    if [[ "$mode" == "https" ]]; then address="https://$domain"; else address="http://$domain:$listen_port"; fi
    say "访问地址：$address"
    say "反代目标：$UPSTREAM"
    if command -v getent >/dev/null 2>&1; then
        say "当前 DNS / hosts 解析（请核对是否为这台 VPS 的公网地址）："
        getent ahosts "$domain" | awk '!seen[$1]++ {print "  " $1}' || warn "暂时无法解析该地址。"
    fi
    confirm "确认保存并应用以上反代" || return 0
    candidate="$WORK/site-new.caddy"
    render_site "$domain" "$mode" "$listen_port" "$UPSTREAM" "$host_mode" "$candidate" || return 1
    "$CADDY_BIN" fmt --overwrite "$candidate" || return 1
    apply_file "$target" "$candidate" || return 1
    ok "已保存反代：$address → $UPSTREAM"
    if [[ "$mode" == "https" ]]; then
        warn "Caddy 会自动申请并续签证书；首次签发请查看菜单中的运行日志。"
        warn "请放行云平台安全组和系统防火墙的 TCP 80、443。"
    else
        warn "请在云平台安全组和系统防火墙放行 TCP $listen_port。"
    fi
}

list_sites() {
    local file count=0
    say ""; say "本菜单管理的站点："
    for file in "$SITES"/*.caddy; do
        [[ -f "$file" ]] || continue
        (( count += 1 ))
        printf '\n[%s] %s\n' "$count" "$(basename "$file" .caddy)"
        sed -n '1,5p' "$file"
    done
    (( count )) || say "暂无站点。"
    say ""; say "已有手工配置仍保留在 $CFG 及其其他导入文件中。"
}

delete_site() {
    check_service || return 1
    list_sites
    local domain target
    ask domain "输入要删除的站点域名/IP（回车取消）" || return 1
    [[ -n "$domain" ]] || return 0
    domain="${domain,,}"
    valid_hostname "$domain" || { err "地址格式错误。"; return 1; }
    target="$SITES/$domain.caddy"
    [[ -f "$target" && ! -L "$target" ]] || { err "没有找到这个菜单站点。"; return 1; }
    confirm "确认删除 $domain 的反代配置" || return 0
    apply_file "$target" "DELETE" || return 1
    ok "已删除 $domain 的反代配置。"
}

show_status() {
    if command -v caddy >/dev/null 2>&1; then caddy version; fi
    systemctl status caddy --no-pager -l || true
    say ""; say "常用监听端口："
    if command -v ss >/dev/null 2>&1; then ss -ltnp '( sport = :80 or sport = :443 or sport = :2019 )'; fi
}

reload_caddy() {
    check_service || return 1
    validate_config || { err "配置校验失败，未重载。"; return 1; }
    activate_config || { err "重载/启动失败，请查看日志。"; return 1; }
    ok "配置已加载。"
}

open_firewall() {
    local port answer active=0
    say "此功能只给已启用的 UFW / firewalld 添加 Web 入站规则。"
    say "云平台安全组需要在服务商控制台另行放行。"
    ask port "需要放行的 TCP 端口（https 填 443，将同时放行 80）" "443" || return 1
    valid_port "$port" || { err "端口必须为 1～65535。"; return 1; }
    port="$((10#$port))"
    [[ "$port" != 2019 ]] || { err "不要将 Caddy 管理端口 2019 开放到公网。"; return 1; }
    confirm "确认放行上述 Web 端口" || return 0
    if command -v ufw >/dev/null 2>&1 && LC_ALL=C ufw status | grep -q '^Status: active'; then
        active=1
        if [[ "$port" == 443 ]]; then ufw allow 80/tcp || return 1; fi
        ufw allow "$port/tcp" || return 1
        if [[ "$port" == 443 ]]; then ufw allow 443/udp || return 1; fi
        ok "UFW 规则已添加。"
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        active=1
        local zone
        say "当前 firewalld 活动区域："
        firewall-cmd --get-active-zones || return 1
        zone="$(firewall-cmd --get-default-zone)" || return 1
        ask answer "规则添加到哪个区域？请按公网网卡的活动区域选择" "$zone" || return 1
        [[ "$answer" =~ ^[a-zA-Z0-9_-]+$ ]] || { err "区域名格式错误。"; return 1; }
        local rule
        local -a rules=("$port/tcp")
        if [[ "$port" == 443 ]]; then rules+=("80/tcp" "443/udp"); fi
        for rule in "${rules[@]}"; do
            firewall-cmd --zone="$answer" --add-port="$rule" || return 1
            firewall-cmd --permanent --zone="$answer" --add-port="$rule" || return 1
        done
        ok "firewalld 区域 $answer 的运行与永久规则已添加。"
    fi
    if (( ! active )); then
        warn "没有检测到已启用的 UFW / firewalld，未改动系统防火墙。"
        warn "请检查云安全组，以及手工配置的 nftables/iptables。"
    fi
}

diagnostics() {
    check_service || return 1
    show_status
    say ""; say "配置校验："
    validate_config || true
    local file domain upstream address mode port code
    for file in "$SITES"/*.caddy; do
        [[ -f "$file" ]] || continue
        domain="$(sed -n 's/^# panel-domain: //p' "$file" | head -1)"
        upstream="$(sed -n 's/^# panel-upstream: //p' "$file" | head -1)"
        mode="$(sed -n 's/^# panel-mode: //p' "$file" | head -1)"
        port="$(sed -n 's/^# panel-port: //p' "$file" | head -1)"
        normalize_upstream "$upstream" || continue
        say ""; say "[$domain] 后端连接检查：$UPSTREAM"
        if command -v curl >/dev/null 2>&1; then
            if code="$(curl --noproxy '*' --proto '=http,https' -sS --connect-timeout 3 --max-time 8 -o /dev/null -w '%{http_code}' "$UPSTREAM")"; then
                say "后端已响应，HTTP $code（鉴权页面返回 401/403 也表示服务可连接）。"
            else
                warn "后端请求失败；检查业务程序、网络和 HTTPS 后端证书。"
            fi
        fi
        if [[ "$mode" == "https" ]]; then address="https://$domain"; else address="http://$domain:$port"; fi
        say "请在自己的浏览器访问：$address"
    done
    say ""; say "最近的 Caddy 日志："
    journalctl -u caddy -n 40 --no-pager || true
    if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" == Enforcing ]]; then
        warn "SELinux 已启用；若后端连通但 Caddy 返回 502，请检查 AVC 拒绝日志和相应策略。"
    fi
    warn "此检查不能代替从公网验证 DNS、云安全组及证书签发。"
}

update_caddy() {
    check_service || return 1
    case "$PKG_KIND" in
        apt) dpkg-query -W -f='${Status}' caddy 2>/dev/null | grep -q '^install ok installed$' || { err "不是 apt 安装的 Caddy，请使用原来的更新方式。"; return 1; } ;;
        dnf) rpm -q caddy >/dev/null 2>&1 || { err "不是 rpm 安装的 Caddy，请使用原来的更新方式。"; return 1; } ;;
    esac
    validate_config || return 1
    confirm "确认通过系统软件包管理器更新 Caddy（服务可能短暂重启）" || return 0
    make_backup || return 1
    case "$PKG_KIND" in
        apt) apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade caddy || return 1 ;;
        dnf) dnf upgrade -y caddy || return 1 ;;
        *) err "此系统不能自动更新，请使用原来的安装方式。"; return 1 ;;
    esac
    check_service && validate_config || return 1
    # 重载不会切换运行中的二进制；更新后需要重启。
    systemctl restart caddy || { err "更新后启动失败，请检查日志；配置备份为 $LAST_BACKUP"; return 1; }
    ok "Caddy 已更新：$(caddy version)"
}

cleanup() {
    local status="$?"
    trap - EXIT INT TERM
    rollback_transaction || status=1
    [[ -z "$WORK" ]] || rm -rf -- "$WORK"
    exit "$status"
}

preflight() {
    local ID ID_LIKE PRETTY_NAME VERSION
    (( BASH_VERSINFO[0] >= 4 )) || { err "请使用 Bash 4 或更新版本。"; return 1; }
    [[ "$(uname -s)" == Linux ]] || { err "本脚本只支持 Linux VPS。"; return 1; }
    (( EUID == 0 )) || { err "请使用 sudo bash 脚本路径，或切换到 root 后运行。"; return 1; }
    if [[ ! -d /run/systemd/system ]] || ! command -v systemctl >/dev/null 2>&1; then
        err "需要正常运行的 systemd；不适用于 Docker 容器、Windows 或普通 NAS 应用容器。"; return 1
    fi
    [[ -r /etc/os-release ]] || { err "无法识别系统。"; return 1; }
    # 系统自带的 os-release 是 root 管理的发行版元数据。
    # shellcheck source=/dev/null
    . /etc/os-release
    OS_ID="${ID:-unknown}"; OS_LIKE="${ID_LIKE:-}"; OS_NAME="${PRETTY_NAME:-$OS_ID}"
    if [[ "$OS_ID" == debian || "$OS_ID" == ubuntu || " $OS_LIKE " == *" debian "* ]]; then
        PKG_KIND="apt"
    elif command -v dnf >/dev/null 2>&1 && [[ "$OS_ID" == fedora || "$OS_ID" == rhel || "$OS_ID" == rocky || "$OS_ID" == almalinux || "$OS_ID" == centos || " $OS_LIKE " == *" rhel "* || " $OS_LIKE " == *" fedora "* ]]; then
        PKG_KIND="dnf"
    else
        warn "当前系统不在自动安装列表中；已有标准 Caddy 服务时仍可管理。"
    fi
    command -v flock >/dev/null 2>&1 || { err "缺少 flock，请先安装 util-linux。"; return 1; }
    install -d -m 0755 /run/lock || return 1
    exec 9>/run/lock/caddy-vps-panel.lock || return 1
    flock -n 9 || { err "已有另一个 Caddy 中文菜单正在操作，请先退出另一个窗口。"; return 1; }
    if ! { exec 3<>/dev/tty; } 2>/dev/null; then
        err "需要 SSH 交互终端；请上传脚本后直接用 bash 运行。"; return 1
    fi
    WORK="$(mktemp -d /tmp/caddy-vps-panel-XXXXXX)" || return 1
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
}

menu() {
    local choice version service
    while true; do
        version="未安装"; service="未运行"
        if command -v caddy >/dev/null 2>&1; then version="$(caddy version 2>/dev/null)"; fi
        systemctl is-active --quiet caddy && service="运行中"
        printf '\n====================================================\n'
        say "  Caddy VPS 中文管理菜单 v$VERSION"
        say "  系统：$OS_NAME"
        say "  Caddy：$version | 服务：$service"
        say "===================================================="
        say "  1. 一键安装 + 添加反向代理（首次使用选这里）"
        say "  2. 添加 / 修改反向代理"
        say "  3. 查看已配置站点"
        say "  4. 删除反向代理"
        say "  5. 查看服务状态与端口"
        say "  6. 查看运行日志"
        say "  7. 校验并重载配置 / 启动 Caddy"
        say "  8. 放行系统防火墙 Web 端口"
        say "  9. 备份配置"
        say " 10. 反代故障检查"
        say " 11. 更新 Caddy"
        say " 12. 仅安装 Caddy"
        say " 13. 查看使用说明"
        say "  0. 退出"
        ask choice "请输入选项" || return 0
        case "$choice" in
            1) install_caddy && add_proxy ;;
            2) add_proxy ;;
            3) list_sites ;;
            4) delete_site ;;
            5) show_status ;;
            6) journalctl -u caddy -n 100 --no-pager ;;
            7) reload_caddy ;;
            8) open_firewall ;;
            9) make_backup && { if [[ -n "$LAST_BACKUP" ]]; then ok "备份完成：$LAST_BACKUP"; else warn "还没有配置可备份。"; fi; } ;;
           10) diagnostics ;;
           11) update_caddy ;;
           12) install_caddy ;;
           13) usage ;;
            0) say "已退出。Caddy 服务会继续在后台运行。"; return 0 ;;
            *) warn "无效选项。" ;;
        esac
        pause_menu
    done
}

main() {
    case "${1:-}" in
        -h|--help) usage; return 0 ;;
        "") ;;
        *) err "不支持这个参数，运行 --help 查看说明。"; return 1 ;;
    esac
    preflight || return 1
    menu
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
