#!/usr/bin/env bash
set -Eeuo pipefail

PROGRAM="${0##*/}"
DRY_RUN=0
ASSUME_YES=0
FULL_UPGRADE=0
ENABLE_FIREWALL=0
ENABLE_BBR=0
HARDEN_SSH=0
DISABLE_PASSWORD=0
SSH_PORT=""
TIMEZONE="Asia/Shanghai"
SSH_PORT_SET=0
TIMEZONE_SET=0
BACKUP_DIR="/root/vps-init-backup-$(date +%Y%m%d-%H%M%S)"

log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
通用 VPS 初始化与 Fail2ban 配置脚本

用法：
  sudo bash vps-init.sh [选项]

默认执行：
  - 更新软件包索引，但不执行系统大版本升级
  - 安装 Fail2ban、CA 证书、curl、时间同步和 QEMU Guest Agent
  - 自动识别 SSH 实际端口并启用 sshd 防暴力破解规则
  - 启用时间同步、QEMU Guest Agent 和定期 TRIM（系统支持时）
  - 保留配置备份，输出执行摘要

选项：
  --yes                 非交互执行
  --full-upgrade        升级所有已安装软件包
  --ssh-port PORT       手动指定 SSH 端口
  --timezone ZONE       设置时区，默认 Asia/Shanghai
  --enable-firewall     启用防火墙，并先放行当前 SSH 端口
  --enable-bbr          系统支持时启用 BBR + fq
  --harden-ssh          添加低风险 SSH 加固配置
  --disable-password    禁用 SSH 密码登录；必须同时使用 --harden-ssh，
                        且当前用户或 root 必须已有 authorized_keys
  --dry-run             只显示计划执行的命令，不修改系统
  -h, --help            显示帮助

示例：
  sudo bash vps-init.sh
  sudo bash vps-init.sh --yes --enable-firewall --enable-bbr
  sudo bash vps-init.sh --ssh-port 2222 --harden-ssh
EOF
}

run() {
  if (( DRY_RUN )); then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

write_file() {
  local path="$1" content="$2"
  if (( DRY_RUN )); then
    printf '[dry-run] write %s\n%s\n' "$path" "$content"
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
}

backup_file() {
  local path="$1"
  local target
  [[ -e "$path" ]] || return 0
  if (( DRY_RUN )); then
    log "将备份 $path 到 $BACKUP_DIR"
    return 0
  fi
  target="${BACKUP_DIR}${path}"
  mkdir -p "$(dirname "$target")"
  cp -a "$path" "$target"
}

confirm() {
  (( ASSUME_YES )) && return 0
  local reply
  read -r -p "即将修改系统配置，是否继续？[y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || die "用户取消"
}

ask_enable() {
  local prompt="$1" variable="$2" reply
  (( ASSUME_YES )) && return 0
  [[ "${!variable}" -eq 1 ]] && return 0
  read -r -p "$prompt [y/N] " reply
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    printf -v "$variable" '%d' 1
  fi
}

prompt_optional_features() {
  (( ASSUME_YES )) && return 0
  printf '\n请选择可选功能，直接按 Enter 表示不开启：\n'
  ask_enable "是否完整升级所有已安装软件包？" FULL_UPGRADE
  ask_enable "是否启用防火墙，并只预先放行当前 SSH 端口？" ENABLE_FIREWALL
  ask_enable "是否在内核支持时启用 BBR + fq？" ENABLE_BBR
  ask_enable "是否启用低风险 SSH 安全加固？" HARDEN_SSH
  if (( HARDEN_SSH )); then
    warn "禁用密码登录前，必须确保 SSH 密钥已经测试可用"
    ask_enable "是否禁用 SSH 密码登录，仅保留密钥认证？" DISABLE_PASSWORD
  fi
}

prompt_runtime_values() {
  (( ASSUME_YES )) && return 0
  local reply

  if (( ! SSH_PORT_SET )); then
    while true; do
      read -r -p "检测到当前 SSH 端口为 ${SSH_PORT}，按 Enter 保持，检测错误时请输入实际端口：" reply
      [[ -z "$reply" ]] && break
      if [[ "$reply" =~ ^[0-9]+$ ]] && (( 10#$reply >= 1 && 10#$reply <= 65535 )); then
        SSH_PORT="$((10#$reply))"
        break
      fi
      warn "端口必须是 1-65535 之间的数字"
    done
  fi

  if (( ! TIMEZONE_SET )); then
    while true; do
      read -r -p "请输入时区，按 Enter 使用 ${TIMEZONE}：" reply
      [[ -z "$reply" ]] && break
      if [[ -e "/usr/share/zoneinfo/$reply" && "$reply" != *".."* ]]; then
        TIMEZONE="$reply"
        break
      fi
      warn "无效时区：$reply，例如 Asia/Shanghai、UTC、Europe/London"
    done
  fi
}

while (($#)); do
  case "$1" in
    --yes) ASSUME_YES=1 ;;
    --full-upgrade) FULL_UPGRADE=1 ;;
    --enable-firewall) ENABLE_FIREWALL=1 ;;
    --enable-bbr) ENABLE_BBR=1 ;;
    --harden-ssh) HARDEN_SSH=1 ;;
    --disable-password) DISABLE_PASSWORD=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --ssh-port)
      (($# >= 2)) || die "--ssh-port 缺少端口"
      SSH_PORT="$2"; SSH_PORT_SET=1; shift
      ;;
    --timezone)
      (($# >= 2)) || die "--timezone 缺少时区"
      TIMEZONE="$2"; TIMEZONE_SET=1; shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知选项：$1（使用 --help 查看帮助）" ;;
  esac
  shift
done

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "请使用 root 或 sudo 执行"
[[ "$SSH_PORT" =~ ^$|^[0-9]+$ ]] || die "SSH 端口必须是数字"
if [[ -n "$SSH_PORT" ]]; then
  (( 10#$SSH_PORT >= 1 && 10#$SSH_PORT <= 65535 )) || die "SSH 端口范围必须是 1-65535"
fi
(( DISABLE_PASSWORD == 0 || HARDEN_SSH == 1 )) || die "--disable-password 必须配合 --harden-ssh"

[[ -r /etc/os-release ]] || die "无法识别 Linux 发行版"
# shellcheck disable=SC1091
. /etc/os-release
OS_ID="${ID:-unknown}"
OS_LIKE="${ID_LIKE:-}"
PKG_FAMILY=""

if command -v apt-get >/dev/null 2>&1; then
  PKG_FAMILY=apt
elif command -v dnf >/dev/null 2>&1; then
  PKG_FAMILY=dnf
elif command -v yum >/dev/null 2>&1; then
  PKG_FAMILY=yum
elif command -v zypper >/dev/null 2>&1; then
  PKG_FAMILY=zypper
elif command -v pacman >/dev/null 2>&1; then
  PKG_FAMILY=pacman
elif command -v apk >/dev/null 2>&1; then
  PKG_FAMILY=apk
else
  die "不支持当前软件包管理器"
fi

detect_ssh_port() {
  local detected=""
  if command -v sshd >/dev/null 2>&1; then
    detected="$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2; exit}' || true)"
  fi
  if [[ -z "$detected" && -r /etc/ssh/sshd_config ]]; then
    detected="$(awk 'tolower($1) == "port" {print $2; exit}' /etc/ssh/sshd_config || true)"
  fi
  printf '%s' "${detected:-22}"
}

[[ -n "$SSH_PORT" ]] || SSH_PORT="$(detect_ssh_port)"
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] || die "未能识别有效 SSH 端口，请使用 --ssh-port 指定"

install_packages() {
  log "更新软件索引并安装基础组件"
  case "$PKG_FAMILY" in
    apt)
      run env DEBIAN_FRONTEND=noninteractive apt-get update
      (( FULL_UPGRADE )) && run env DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade
      run env DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl fail2ban chrony qemu-guest-agent
      ;;
    dnf)
      run dnf -y makecache
      (( FULL_UPGRADE )) && run dnf -y upgrade
      if ! rpm -q fail2ban >/dev/null 2>&1; then run dnf -y install epel-release || true; fi
      run dnf -y install ca-certificates curl fail2ban chrony qemu-guest-agent
      ;;
    yum)
      run yum -y makecache
      (( FULL_UPGRADE )) && run yum -y update
      if ! rpm -q fail2ban >/dev/null 2>&1; then run yum -y install epel-release || true; fi
      run yum -y install ca-certificates curl fail2ban chrony qemu-guest-agent
      ;;
    zypper)
      run zypper --non-interactive refresh
      (( FULL_UPGRADE )) && run zypper --non-interactive update
      run zypper --non-interactive install ca-certificates curl fail2ban chrony qemu-guest-agent
      ;;
    pacman)
      run pacman -Sy --noconfirm
      (( FULL_UPGRADE )) && run pacman -Su --noconfirm
      run pacman -S --needed --noconfirm ca-certificates curl fail2ban chrony qemu-guest-agent
      ;;
    apk)
      run apk update
      (( FULL_UPGRADE )) && run apk upgrade
      run apk add ca-certificates curl fail2ban chrony qemu-guest-agent
      ;;
  esac
}

service_enable_now() {
  local service="$1"
  if command -v systemctl >/dev/null 2>&1; then
    run systemctl enable --now "$service"
  elif command -v rc-update >/dev/null 2>&1; then
    run rc-update add "$service" default || true
    run rc-service "$service" restart || true
  else
    warn "无法自动管理服务：$service"
  fi
}

configure_time_and_guest() {
  log "配置时间同步和虚拟机组件"
  if command -v timedatectl >/dev/null 2>&1; then
    run timedatectl set-timezone "$TIMEZONE" || warn "时区设置失败：$TIMEZONE"
  elif [[ -e "/usr/share/zoneinfo/$TIMEZONE" ]]; then
    run ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
  fi

  if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files chronyd.service --no-legend 2>/dev/null | grep -q chronyd; then
      service_enable_now chronyd
    else
      service_enable_now chrony || warn "chrony 服务未能启用"
    fi
    service_enable_now qemu-guest-agent || warn "QEMU Guest Agent 未能启用，非 QEMU/KVM 环境可忽略"
    if systemctl list-unit-files fstrim.timer --no-legend 2>/dev/null | grep -q fstrim; then
      run systemctl enable --now fstrim.timer || warn "TRIM 定时器未能启用"
    fi
  else
    service_enable_now chronyd
    service_enable_now qemu-guest-agent
  fi
}

configure_fail2ban() {
  log "配置 Fail2ban SSH 防护"
  local backend="auto"
  command -v journalctl >/dev/null 2>&1 && backend="systemd"
  local jail_file="/etc/fail2ban/jail.d/sshd.local"
  backup_file "$jail_file"
  write_file "$jail_file" "[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
bantime.increment = true
bantime.factor = 2
bantime.maxtime = 1w
usedns = no
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ${SSH_PORT}
backend = ${backend}"

  if (( ! DRY_RUN )); then
    fail2ban-client -t || die "Fail2ban 配置检查失败，备份位于 $BACKUP_DIR"
  fi
  service_enable_now fail2ban
  if (( ! DRY_RUN )); then
    fail2ban-client reload || true
    fail2ban-client status sshd || warn "sshd jail 尚未启动，请检查系统认证日志"
  fi
}

configure_firewall() {
  (( ENABLE_FIREWALL )) || return 0
  log "配置防火墙"
  if command -v ufw >/dev/null 2>&1 || [[ "$PKG_FAMILY" == apt ]]; then
    command -v ufw >/dev/null 2>&1 || run env DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
    run ufw allow "${SSH_PORT}/tcp"
    run ufw default deny incoming
    run ufw default allow outgoing
    run ufw --force enable
  elif command -v firewall-cmd >/dev/null 2>&1; then
    service_enable_now firewalld
    run firewall-cmd --permanent --add-port="${SSH_PORT}/tcp"
    run firewall-cmd --reload
  elif [[ "$PKG_FAMILY" == dnf || "$PKG_FAMILY" == yum ]]; then
    run "$PKG_FAMILY" -y install firewalld
    service_enable_now firewalld
    run firewall-cmd --permanent --add-port="${SSH_PORT}/tcp"
    run firewall-cmd --reload
  elif [[ "$PKG_FAMILY" == zypper ]]; then
    run zypper --non-interactive install firewalld
    service_enable_now firewalld
    run firewall-cmd --permanent --add-port="${SSH_PORT}/tcp"
    run firewall-cmd --reload
  elif [[ "$PKG_FAMILY" == pacman ]]; then
    run pacman -S --needed --noconfirm ufw
    run ufw allow "${SSH_PORT}/tcp"
    run ufw default deny incoming
    run ufw default allow outgoing
    run ufw --force enable
  else
    die "当前系统未找到受支持的防火墙前端；为避免误封，未自动配置"
  fi
}

configure_bbr() {
  (( ENABLE_BBR )) || return 0
  log "检查并启用 BBR"
  if (( ! DRY_RUN )); then
    modprobe tcp_bbr 2>/dev/null || true
    sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr \
      || { warn "当前内核不支持 BBR，跳过"; return 0; }
  fi
  local sysctl_file="/etc/sysctl.d/99-vps-init-bbr.conf"
  backup_file "$sysctl_file"
  write_file "$sysctl_file" "net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr"
  run sysctl --system
}

has_authorized_key() {
  local invoking_user="${SUDO_USER:-root}" home_dir="/root"
  if [[ "$invoking_user" != root ]]; then
    home_dir="$(getent passwd "$invoking_user" | cut -d: -f6)"
  fi
  [[ -s "$home_dir/.ssh/authorized_keys" || -s /root/.ssh/authorized_keys ]]
}

configure_ssh() {
  (( HARDEN_SSH )) || return 0
  log "配置 SSH 加固"
  if (( DISABLE_PASSWORD )) && ! has_authorized_key; then
    die "未找到 authorized_keys，拒绝禁用密码登录"
  fi

  local dropin_dir="/etc/ssh/sshd_config.d"
  local ssh_file="$dropin_dir/99-vps-init-hardening.conf"
  local main_file="/etc/ssh/sshd_config"
  if ! grep -Eiq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$main_file"; then
    backup_file "$main_file"
    if (( DRY_RUN )); then
      log "将为 $main_file 添加 sshd_config.d Include 支持"
    else
      local temp_file
      temp_file="$(mktemp)"
      printf 'Include /etc/ssh/sshd_config.d/*.conf\n' > "$temp_file"
      cat "$main_file" >> "$temp_file"
      install -m 600 "$temp_file" "$main_file"
      rm -f "$temp_file"
    fi
  fi
  backup_file "$ssh_file"
  local password_line="# PasswordAuthentication 保持系统当前设置"
  local root_line="# PermitRootLogin 保持系统当前设置"
  if (( DISABLE_PASSWORD )); then
    password_line="PasswordAuthentication no"
    root_line="PermitRootLogin prohibit-password"
  fi
  write_file "$ssh_file" "# Managed by vps-init.sh
PermitEmptyPasswords no
MaxAuthTries 4
LoginGraceTime 30
X11Forwarding no
UseDNS no
${password_line}
${root_line}"

  if (( ! DRY_RUN )); then
    if ! sshd -t; then
      rm -f "$ssh_file"
      die "SSH 配置检查失败，已移除新配置"
    fi
  fi
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files ssh.service --no-legend 2>/dev/null | grep -q ssh; then
      run systemctl reload ssh
    else
      run systemctl reload sshd
    fi
  else
    run rc-service sshd reload
  fi
}

prompt_runtime_values
[[ -e "/usr/share/zoneinfo/$TIMEZONE" && "$TIMEZONE" != *".."* ]] \
  || die "无效时区：$TIMEZONE"
prompt_optional_features
log "系统：${PRETTY_NAME:-$OS_ID}"
log "软件包管理器：$PKG_FAMILY"
log "SSH 端口：$SSH_PORT"
log "时区：$TIMEZONE"
log "完整升级：$([[ $FULL_UPGRADE -eq 1 ]] && echo 开启 || echo 关闭)"
log "防火墙：$([[ $ENABLE_FIREWALL -eq 1 ]] && echo 开启 || echo 关闭)"
log "BBR：$([[ $ENABLE_BBR -eq 1 ]] && echo 开启 || echo 关闭)"
log "SSH 加固：$([[ $HARDEN_SSH -eq 1 ]] && echo 开启 || echo 关闭)"
log "禁用 SSH 密码登录：$([[ $DISABLE_PASSWORD -eq 1 ]] && echo 开启 || echo 关闭)"
(( ENABLE_FIREWALL )) && warn "将启用防火墙；脚本会先放行 TCP/$SSH_PORT"
(( DISABLE_PASSWORD )) && warn "将禁用 SSH 密码登录，请确认密钥登录已经验证成功"
confirm

install_packages
configure_time_and_guest
configure_fail2ban
configure_firewall
configure_bbr
configure_ssh

log "初始化完成"
printf '\n系统：%s\nSSH 端口：%s\nFail2ban：已配置 sshd jail\n' "${PRETTY_NAME:-$OS_ID}" "$SSH_PORT"
printf '防火墙：%s\nBBR：%s\nSSH 加固：%s\n' \
  "$([[ $ENABLE_FIREWALL -eq 1 ]] && echo 已启用 || echo 未改动)" \
  "$([[ $ENABLE_BBR -eq 1 ]] && echo 已请求启用 || echo 未改动)" \
  "$([[ $HARDEN_SSH -eq 1 ]] && echo 已配置 || echo 未改动)"
(( DRY_RUN )) || printf '备份目录：%s\n' "$BACKUP_DIR"
printf '\n检查命令：\n  fail2ban-client status sshd\n  ss -lntp\n  systemctl --failed\n'
