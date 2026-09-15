#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

PORT="${PORT:-443}"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="${CONFIG_DIR}/config.json"
BACKUP_DIR="/var/backups/sing-box-reality"
INFO_FILE="/root/vless-reality-info.txt"
SING_BOX_BIN="/usr/bin/sing-box"

if [[ -t 1 ]]; then
    GREEN='\033[32m'
    YELLOW='\033[33m'
    RED='\033[31m'
    CYAN='\033[36m'
    RESET='\033[0m'
else
    GREEN=''
    YELLOW=''
    RED=''
    CYAN=''
    RESET=''
fi

log() {
    printf '%b%s%b\n' "$GREEN" "$*" "$RESET"
}

warn() {
    printf '%b%s%b\n' "$YELLOW" "$*" "$RESET" >&2
}

die() {
    printf '%b%s%b\n' "$RED" "$*" "$RESET" >&2
    exit 1
}

STATE_CHANGED="no"
HAD_CONFIG="no"
HAD_INFO="no"
OLD_SB_ACTIVE="no"
OLD_SB_ENABLED="disabled"
BACKUP_FILE=""
INFO_BACKUP_FILE=""
KEYRING_TMP=""
NEW_CONFIG=""
NEW_INFO=""

rollback() {
    warn "安装失败，正在恢复原配置和服务状态..."

    systemctl stop sing-box >/dev/null 2>&1 || true

    if [[ "$HAD_CONFIG" == "yes" && -f "$BACKUP_FILE" ]]; then
        cp -a "$BACKUP_FILE" "$CONFIG_FILE" || true
    else
        rm -f "$CONFIG_FILE"
    fi

    if [[ "$HAD_INFO" == "yes" && -f "$INFO_BACKUP_FILE" ]]; then
        cp -a "$INFO_BACKUP_FILE" "$INFO_FILE" || true
    else
        rm -f "$INFO_FILE"
    fi

    case "$OLD_SB_ENABLED" in
        enabled) systemctl enable sing-box >/dev/null 2>&1 || true ;;
        disabled) systemctl disable sing-box >/dev/null 2>&1 || true ;;
    esac

    if [[ "$OLD_SB_ACTIVE" == "yes" ]]; then
        systemctl restart sing-box >/dev/null 2>&1 || true
    fi
}

on_exit() {
    local exit_code=$?
    trap - EXIT INT TERM
    set +e

    if [[ $exit_code -ne 0 && "$STATE_CHANGED" == "yes" ]]; then
        rollback
    fi

    [[ -n "$KEYRING_TMP" ]] && rm -f "$KEYRING_TMP"
    [[ -n "$NEW_CONFIG" ]] && rm -f "$NEW_CONFIG"
    [[ -n "$NEW_INFO" ]] && rm -f "$NEW_INFO"
    exit "$exit_code"
}

trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%b' "$CYAN"
printf '%s\n' '================================================'
printf '%s\n' '     IPv6-only VLESS Reality Installer'
printf '%s\n' '      sing-box + XTLS Vision'
printf '%s\n' '================================================'
printf '%b' "$RESET"

[[ "$(id -u)" -eq 0 ]] || die "请使用 root 用户运行。"
[[ "$PORT" =~ ^[0-9]+$ ]] || die "PORT 必须是 1-65535 的整数。"
(( PORT >= 1 && PORT <= 65535 )) || die "PORT 必须是 1-65535 的整数。"
[[ -f /etc/os-release ]] || die "无法识别 Linux 系统。"

# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}" in
    debian|ubuntu) ;;
    *) die "本脚本只支持 Debian 和 Ubuntu。" ;;
esac

[[ -d /run/systemd/system ]] || die "当前系统没有运行 systemd。"
command -v systemctl >/dev/null 2>&1 || die "找不到 systemctl。"

log "[1/9] 安装基础依赖..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl ca-certificates openssl iproute2 coreutils

log "[2/9] 检测公网 IPv6..."
IPV6=""
for url in https://api64.ipify.org https://icanhazip.com; do
    result="$(curl -6 -fsS --connect-timeout 5 --max-time 10 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ "$result" == *:* && "$result" =~ ^[0-9A-Fa-f:]+$ ]]; then
        IPV6="$result"
        break
    fi
done

[[ -n "$IPV6" ]] || {
    ip -6 address || true
    ip -6 route || true
    die "没有检测到可正常访问互联网的公网 IPv6。"
}

LOCAL_ROUTE="$(ip -6 route get "$IPV6" 2>/dev/null || true)"
[[ " $LOCAL_ROUTE " == *" local "* ]] || die "公网 IPv6 ${IPV6} 未直接配置在本机；为避免错误监听，脚本不支持 NAT66 场景。"
printf '公网 IPv6：%b%s%b\n' "$CYAN" "$IPV6" "$RESET"

NATIVE_IPV4="$(curl -4 -fsS --connect-timeout 3 --max-time 5 https://api.ipify.org 2>/dev/null | tr -d '[:space:]' || true)"
DNS64_ADDRESS="$(
    getent ahostsv6 ipv4only.arpa 2>/dev/null |
        awk '$1 ~ /:/ && $1 !~ /^::ffff:/ { print $1; exit }' || true
)"

if [[ -n "$NATIVE_IPV4" ]]; then
    IPV4_STATUS="存在原生 IPv4 出口：${NATIVE_IPV4}"
elif [[ -n "$DNS64_ADDRESS" ]]; then
    IPV4_STATUS="无原生 IPv4；检测到 DNS64：${DNS64_ADDRESS}（NAT64 数据通路未单独验证）"
else
    IPV4_STATUS="未检测到原生 IPv4 或 DNS64；访问 IPv4-only 目标可能失败"
fi
printf '%s\n' "$IPV4_STATUS"

log "[3/9] 从官方 APT 仓库安装 sing-box..."
mkdir -p /etc/apt/keyrings
KEYRING_TMP="$(mktemp /etc/apt/keyrings/.sagernet.asc.XXXXXX)"
curl -fsSL --retry 3 --connect-timeout 10 https://sing-box.app/gpg.key -o "$KEYRING_TMP"
install -m 0644 "$KEYRING_TMP" /etc/apt/keyrings/sagernet.asc
rm -f "$KEYRING_TMP"
KEYRING_TMP=""

cat > /etc/apt/sources.list.d/sagernet.sources <<'APT'
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
APT

apt-get update
apt-get install -y sing-box
[[ -x "$SING_BOX_BIN" ]] || die "官方 sing-box 安装失败。"
systemctl cat sing-box >/dev/null 2>&1 || die "没有找到 sing-box.service。"
[[ "$(systemctl is-enabled sing-box 2>/dev/null || true)" != "masked" ]] || die "sing-box.service 已被屏蔽，请先执行 systemctl unmask sing-box。"
"$SING_BOX_BIN" version

log "[4/9] 选择可通过 IPv6 访问的 Reality 握手目标..."
SNI=""
REALITY_IP=""
REALITY_HOSTS=(
    www.microsoft.com
    www.apple.com
    www.cloudflare.com
    www.amazon.com
)

for host in "${REALITY_HOSTS[@]}"; do
    printf '测试：%s\n' "$host"

    while IFS= read -r host_v6; do
        [[ -n "$host_v6" ]] || continue
        printf '  IPv6：%s\n' "$host_v6"

        if curl -6 -sS --connect-timeout 5 --max-time 10 --tlsv1.3 \
            --resolve "${host}:443:[${host_v6}]" \
            -o /dev/null "https://${host}/"; then
            SNI="$host"
            REALITY_IP="$host_v6"
            break 2
        fi
    done < <(
        getent ahostsv6 "$host" 2>/dev/null |
            awk '$1 ~ /:/ && $1 !~ /^::ffff:/ && !seen[$1]++ { print $1 }'
    )
done

[[ -n "$SNI" && -n "$REALITY_IP" ]] || die "没有找到可通过 IPv6 完成 TLS 1.3 握手的 Reality 目标。"
printf 'Reality SNI：%b%s%b\n' "$CYAN" "$SNI" "$RESET"
printf 'Reality 目标 IPv6：%b%s%b\n' "$CYAN" "$REALITY_IP" "$RESET"

log "[5/9] 生成 UUID 和 Reality 密钥..."
UUID="$("$SING_BOX_BIN" generate uuid)"
KEYPAIR="$("$SING_BOX_BIN" generate reality-keypair)"
PRIVATE_KEY="$(printf '%s\n' "$KEYPAIR" | awk -F ': *' 'tolower($1) ~ /privatekey|private key/ { print $2; exit }')"
PUBLIC_KEY="$(printf '%s\n' "$KEYPAIR" | awk -F ': *' 'tolower($1) ~ /publickey|public key/ { print $2; exit }')"
SHORT_ID="$(openssl rand -hex 8)"

[[ -n "$UUID" ]] || die "UUID 生成失败。"
[[ -n "$PRIVATE_KEY" && -n "$PUBLIC_KEY" ]] || die "Reality 密钥解析失败。"

log "[6/9] 创建并检查新配置..."
mkdir -p "$CONFIG_DIR" "$BACKUP_DIR"

shopt -s nullglob
for existing_config in "$CONFIG_DIR"/*.json; do
    [[ "$existing_config" == "$CONFIG_FILE" ]] || die "检测到额外配置文件 ${existing_config}；为避免合并冲突，脚本已停止。"
done
shopt -u nullglob

NEW_CONFIG="$(mktemp "${CONFIG_DIR}/.config.json.new.XXXXXX")"
cat > "$NEW_CONFIG" <<CONFIG
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "${IPV6}",
      "listen_port": ${PORT},
      "users": [
        {
          "name": "user",
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${SNI}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${REALITY_IP}",
            "server_port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": [
            "${SHORT_ID}"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
CONFIG
chmod 600 "$NEW_CONFIG"
"$SING_BOX_BIN" check -c "$NEW_CONFIG"

VLESS_URL="vless://${UUID}@[${IPV6}]:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision#IPv6-Reality"
NEW_INFO="$(mktemp /root/.vless-reality-info.new.XXXXXX)"
cat > "$NEW_INFO" <<INFO
IPv6-only VLESS Reality
========================
服务器 IPv6：${IPV6}
端口：${PORT}
协议：VLESS
UUID：${UUID}
Flow：xtls-rprx-vision
传输：TCP
TLS：Reality
Reality SNI：${SNI}
Fingerprint：chrome
Reality Public Key：${PUBLIC_KEY}
Reality Short ID：${SHORT_ID}
IPv4 / DNS64：${IPV4_STATUS}

VLESS 分享链接
===============
${VLESS_URL}
INFO
chmod 600 "$NEW_INFO"

if [[ -f "$CONFIG_FILE" ]]; then
    HAD_CONFIG="yes"
    BACKUP_FILE="${BACKUP_DIR}/config.json.$(date +%Y%m%d-%H%M%S).$$"
    cp -a "$CONFIG_FILE" "$BACKUP_FILE"
fi

if [[ -f "$INFO_FILE" ]]; then
    HAD_INFO="yes"
    INFO_BACKUP_FILE="${BACKUP_DIR}/vless-reality-info.txt.$(date +%Y%m%d-%H%M%S).$$"
    cp -a "$INFO_FILE" "$INFO_BACKUP_FILE"
fi

OLD_SB_ACTIVE="no"
systemctl is-active --quiet sing-box && OLD_SB_ACTIVE="yes"
OLD_SB_ENABLED="$(systemctl is-enabled sing-box 2>/dev/null || true)"

log "[7/9] 替换配置并启动服务..."
STATE_CHANGED="yes"
systemctl stop sing-box

if [[ -n "$(ss -H -ltn6 "sport = :${PORT}" 2>/dev/null || true)" ]]; then
    ss -lntp6 "sport = :${PORT}" || true
    die "IPv6 TCP ${PORT} 已被其他程序占用。"
fi

install -m 0600 "$NEW_CONFIG" "$CONFIG_FILE"
systemctl enable sing-box
systemctl restart sing-box

SERVICE_READY="no"
for _ in {1..10}; do
    if systemctl is-active --quiet sing-box && [[ -n "$(ss -H -ltn6 "sport = :${PORT}" 2>/dev/null || true)" ]]; then
        SERVICE_READY="yes"
        break
    fi
    sleep 1
done

if [[ "$SERVICE_READY" != "yes" ]]; then
    journalctl -u sing-box --no-pager -n 50 || true
    die "sing-box 未能正常启动并监听 IPv6 TCP ${PORT}。"
fi

install -m 0600 "$NEW_INFO" "$INFO_FILE"

log "[8/9] 检查本机防火墙..."
if command -v ufw >/dev/null 2>&1 && LC_ALL=C ufw status 2>/dev/null | grep -q '^Status: active'; then
    if grep -Eq '^[[:space:]]*IPV6[[:space:]]*=[[:space:]]*no' /etc/default/ufw 2>/dev/null; then
        die "UFW 已启用但 IPv6 支持被关闭，请先在 /etc/default/ufw 中设置 IPV6=yes。"
    fi

    ufw allow proto tcp from ::/0 to "$IPV6" port "$PORT"
fi

STATE_CHANGED="no"

log "[9/9] 安装完成。"
printf '\n服务器 IPv6： %b%s%b\n' "$CYAN" "$IPV6" "$RESET"
printf '端口：         %b%s%b\n' "$CYAN" "$PORT" "$RESET"
printf 'UUID：         %b%s%b\n' "$CYAN" "$UUID" "$RESET"
printf 'Reality SNI：  %b%s%b\n' "$CYAN" "$SNI" "$RESET"
printf 'Public Key：   %b%s%b\n' "$CYAN" "$PUBLIC_KEY" "$RESET"
printf 'Short ID：     %b%s%b\n' "$CYAN" "$SHORT_ID" "$RESET"
printf '\n%s\n\n%s\n' "$IPV4_STATUS" "$VLESS_URL"
printf '\n节点信息：%s\n' "$INFO_FILE"
printf '服务状态：systemctl status sing-box --no-pager\n'
printf '实时日志：journalctl -u sing-box -f\n'
warn "云服务器安全组还必须允许 IPv6 TCP ${PORT}。"
