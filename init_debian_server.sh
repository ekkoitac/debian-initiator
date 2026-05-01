#!/usr/bin/env bash
# Debian 服务器中文初始化脚本
# 适用范围：Debian 11/12/13，新装或接近新装的 Web 通用 + 开发构建服务器。

# 如果用户误用 sh 执行，本段会在解析到 Bash 专属语法前自动切回 bash。
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  printf '\n[错误] 本脚本需要 bash，请先安装 bash，或使用：sudo bash %s\n' "$0" >&2
  exit 1
fi

set -Eeuo pipefail

# =========================
# 可按需覆盖的默认配置；交互模式下会询问并更新这些值
# =========================
# 是否启用中国大陆镜像。默认 0：保持系统原有源；设置为 1：写入国内 Debian/Docker 源，并设置 npm 国内 registry。
USE_CN_MIRROR="${USE_CN_MIRROR:-0}"

# SSH 端口只用于 UFW 放行，不会修改 SSH 服务配置。
SSH_PORT="${SSH_PORT:-22}"

# Node.js LTS 主版本。2026 年默认使用 Node.js 24 LTS。
NODE_MAJOR="${NODE_MAJOR:-24}"

INTERACTIVE="${INTERACTIVE:-1}"
INSTALL_BASE_TOOLS="${INSTALL_BASE_TOOLS:-1}"
INSTALL_SECURITY="${INSTALL_SECURITY:-1}"
INSTALL_DOCKER="${INSTALL_DOCKER:-1}"
INSTALL_NODE="${INSTALL_NODE:-1}"
INSTALL_NGINX="${INSTALL_NGINX:-1}"
INSTALL_PYTHON_DEV="${INSTALL_PYTHON_DEV:-1}"

export DEBIAN_FRONTEND=noninteractive

log() {
  printf '\n\033[1;32m[信息]\033[0m %s\n' "$*"
}

warn() {
  printf '\n\033[1;33m[提醒]\033[0m %s\n' "$*" >&2
}

die() {
  printf '\n\033[1;31m[错误]\033[0m %s\n' "$*" >&2
  exit 1
}

run() {
  printf '\033[1;34m[执行]\033[0m %s\n' "$*"
  "$@"
}

is_enabled() {
  [[ "${1:-0}" == "1" ]]
}

yes_no_text() {
  if is_enabled "$1"; then
    printf '是'
  else
    printf '否'
  fi
}

is_interactive() {
  [[ "${INTERACTIVE}" == "1" && -t 0 && -t 1 ]]
}

prompt_yes_no() {
  local var_name="$1"
  local message="$2"
  local default_value="${!var_name}"
  local default_hint="Y/n"
  local answer=""

  if [[ "${default_value}" != "1" ]]; then
    default_hint="y/N"
  fi

  while true; do
    read -r -p "${message} [${default_hint}] " answer
    answer="${answer,,}"

    if [[ -z "${answer}" ]]; then
      printf -v "${var_name}" '%s' "${default_value}"
      return 0
    fi

    case "${answer}" in
      y|yes|1|是|好|安装|启用)
        printf -v "${var_name}" '1'
        return 0
        ;;
      n|no|0|否|不|不安装|禁用)
        printf -v "${var_name}" '0'
        return 0
        ;;
      *)
        warn "请输入 y 或 n。"
        ;;
    esac
  done
}

prompt_value() {
  local var_name="$1"
  local message="$2"
  local default_value="${!var_name}"
  local answer=""

  read -r -p "${message} [默认：${default_value}] " answer
  if [[ -n "${answer}" ]]; then
    printf -v "${var_name}" '%s' "${answer}"
  fi
}

validate_choices() {
  if ! [[ "${SSH_PORT}" =~ ^[0-9]+$ ]] || (( SSH_PORT < 1 || SSH_PORT > 65535 )); then
    die "SSH_PORT 必须是 1-65535 之间的端口号，当前值：${SSH_PORT}"
  fi

  if ! [[ "${NODE_MAJOR}" =~ ^[0-9]+$ ]]; then
    die "NODE_MAJOR 必须是数字，例如 24 或 22，当前值：${NODE_MAJOR}"
  fi
}

confirm_choices() {
  printf '\n%s\n' "==================== 即将执行的初始化选项 ===================="
  printf '%-24s %s\n' "启用国内镜像：" "$(yes_no_text "${USE_CN_MIRROR}")"
  printf '%-24s %s\n' "安装基础运维工具：" "$(yes_no_text "${INSTALL_BASE_TOOLS}")"
  printf '%-24s %s\n' "安装 Nginx：" "$(yes_no_text "${INSTALL_NGINX}")"
  printf '%-24s %s\n' "安装 Docker/Compose：" "$(yes_no_text "${INSTALL_DOCKER}")"
  printf '%-24s %s\n' "安装 Node.js：" "$(yes_no_text "${INSTALL_NODE}")"
  if is_enabled "${INSTALL_NODE}"; then
    printf '%-24s %s\n' "Node.js 主版本：" "${NODE_MAJOR}.x"
  fi
  printf '%-24s %s\n' "安装 Python 开发环境：" "$(yes_no_text "${INSTALL_PYTHON_DEV}")"
  printf '%-24s %s\n' "配置 UFW/Fail2ban/自动更新：" "$(yes_no_text "${INSTALL_SECURITY}")"
  if is_enabled "${INSTALL_SECURITY}"; then
    printf '%-24s %s\n' "UFW 放行 SSH 端口：" "${SSH_PORT}/tcp"
  fi
  printf '%s\n' "==============================================================="

  local answer=""
  while true; do
    read -r -p "确认开始执行？[Y/n] " answer
    answer="${answer,,}"
    case "${answer}" in
      ''|y|yes|1|是|好|开始)
        return 0
        ;;
      n|no|0|否|取消)
        die "已取消执行，没有继续修改系统。"
        ;;
      *)
        warn "请输入 y 或 n。"
        ;;
    esac
  done
}

collect_interactive_choices() {
  if ! is_interactive; then
    log "当前不是交互式终端，使用默认配置或环境变量配置继续执行。"
    validate_choices
    return 0
  fi

  printf '\n%s\n' "==================== Debian 服务器初始化向导 ===================="
  printf '%s\n' "直接回车会使用推荐默认值；本脚本不会修改 SSH 服务配置。"
  printf '%s\n\n' "你也可以用环境变量预设，例如：USE_CN_MIRROR=1 INSTALL_NODE=0 sudo bash init_debian_server.sh"

  prompt_yes_no USE_CN_MIRROR "是否启用中国大陆镜像源"
  prompt_yes_no INSTALL_BASE_TOOLS "是否安装基础运维工具"
  prompt_yes_no INSTALL_NGINX "是否安装并启用 Nginx"
  prompt_yes_no INSTALL_DOCKER "是否安装 Docker Engine + Compose 插件"
  prompt_yes_no INSTALL_NODE "是否安装 Node.js + npm"
  if is_enabled "${INSTALL_NODE}"; then
    prompt_value NODE_MAJOR "请输入 Node.js 主版本"
  fi
  prompt_yes_no INSTALL_PYTHON_DEV "是否安装 Python 开发环境"
  prompt_yes_no INSTALL_SECURITY "是否配置 UFW、Fail2ban、自动安全更新"
  if is_enabled "${INSTALL_SECURITY}"; then
    prompt_value SSH_PORT "请输入需要 UFW 放行的 SSH 端口"
  fi

  validate_choices
  confirm_choices
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "请使用 root 用户执行，或使用 sudo：sudo bash init_debian_server.sh"
  fi
}

load_os_info() {
  if [[ ! -r /etc/os-release ]]; then
    die "无法读取 /etc/os-release，无法确认系统版本。"
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  OS_ID="${ID:-}"
  OS_VERSION_ID="${VERSION_ID:-}"
  OS_CODENAME="${VERSION_CODENAME:-}"
  OS_PRETTY_NAME="${PRETTY_NAME:-未知 Debian 系统}"
  ARCH="$(dpkg --print-architecture)"

  if [[ "${OS_ID}" != "debian" ]]; then
    die "当前系统不是 Debian，本脚本仅支持 Debian 11/12/13。检测到：${OS_PRETTY_NAME}"
  fi

  case "${OS_VERSION_ID}" in
    11|12|13) ;;
    *)
      die "当前 Debian 版本不在支持范围内。本脚本支持 Debian 11/12/13，检测到：${OS_PRETTY_NAME}"
      ;;
  esac

  if [[ -z "${OS_CODENAME}" ]]; then
    case "${OS_VERSION_ID}" in
      11) OS_CODENAME="bullseye" ;;
      12) OS_CODENAME="bookworm" ;;
      13) OS_CODENAME="trixie" ;;
    esac
  fi

  log "检测到系统：${OS_PRETTY_NAME}，代号：${OS_CODENAME}，架构：${ARCH}"
}

apt_update() {
  run apt-get update
}

apt_install() {
  run apt-get install -y --no-install-recommends "$@"
}

package_available() {
  apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}' | grep -qv '(none)'
}

install_if_available() {
  local package="$1"
  if package_available "${package}"; then
    apt_install "${package}"
  else
    warn "当前软件源中没有找到 ${package}，已跳过。"
  fi
}

install_repository_tools() {
  if ! is_enabled "${INSTALL_DOCKER}" && ! is_enabled "${INSTALL_NODE}"; then
    return 0
  fi

  log "安装第三方 apt 仓库所需工具。"
  apt_update
  apt_install ca-certificates curl gnupg lsb-release
}

configure_cn_apt_mirror() {
  [[ "${USE_CN_MIRROR}" == "1" ]] || return 0

  log "启用国内 Debian 镜像源配置。"

  local backup_dir="/etc/apt/backup-before-init-$(date +%Y%m%d%H%M%S)"
  mkdir -p "${backup_dir}"

  if [[ -f /etc/apt/sources.list ]]; then
    cp -a /etc/apt/sources.list "${backup_dir}/sources.list"
    : > /etc/apt/sources.list
  fi

  if [[ -f /etc/apt/sources.list.d/debian.sources ]]; then
    cp -a /etc/apt/sources.list.d/debian.sources "${backup_dir}/debian.sources"
    mv /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list.d/debian.sources.disabled-by-init-script
  fi

  local components="main contrib non-free"
  if [[ "${OS_VERSION_ID}" != "11" ]]; then
    components="main contrib non-free non-free-firmware"
  fi

  cat > /etc/apt/sources.list.d/debian-cn.sources <<EOF
Types: deb
URIs: https://mirrors.ustc.edu.cn/debian
Suites: ${OS_CODENAME} ${OS_CODENAME}-updates
Components: ${components}
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://mirrors.ustc.edu.cn/debian-security
Suites: ${OS_CODENAME}-security
Components: ${components}
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

  log "已写入 /etc/apt/sources.list.d/debian-cn.sources；原始源已备份到 ${backup_dir}"
}

install_base_packages() {
  if ! is_enabled "${INSTALL_BASE_TOOLS}"; then
    warn "已选择跳过基础运维工具。"
    return 0
  fi

  log "更新 apt 索引并安装基础运维工具。"
  apt_update

  local base_packages=(
    curl
    wget
    git
    vim
    nano
    htop
    tmux
    unzip
    zip
    tar
    jq
    rsync
    ca-certificates
    gnupg
    lsb-release
    dnsutils
    net-tools
    iproute2
    ufw
    fail2ban
    unattended-upgrades
    chrony
    locales
    build-essential
  )

  apt_install "${base_packages[@]}"
  install_if_available btop
}

configure_locales() {
  if ! is_enabled "${INSTALL_BASE_TOOLS}"; then
    return 0
  fi

  log "生成常用 UTF-8 语言环境。"

  sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  sed -i 's/^# *\(zh_CN.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  run locale-gen
}

configure_unattended_upgrades() {
  log "启用自动安全更新。"

  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

  if systemctl list-unit-files apt-daily.timer >/dev/null 2>&1; then
    run systemctl enable --now apt-daily.timer
  fi

  if systemctl list-unit-files apt-daily-upgrade.timer >/dev/null 2>&1; then
    run systemctl enable --now apt-daily-upgrade.timer
  fi
}

install_nginx() {
  [[ "${INSTALL_NGINX}" == "1" ]] || return 0

  log "安装并启用 Nginx。"
  apt_update
  apt_install nginx
  run systemctl enable --now nginx
}

install_python_dev() {
  [[ "${INSTALL_PYTHON_DEV}" == "1" ]] || return 0

  log "安装 Python 开发环境。"
  apt_update
  apt_install python3 python3-pip python3-venv
  install_if_available pipx
}

install_docker() {
  [[ "${INSTALL_DOCKER}" == "1" ]] || return 0

  log "配置 Docker 官方 apt 仓库。"

  local docker_repo_url="https://download.docker.com/linux/debian"
  local docker_gpg_url="https://download.docker.com/linux/debian/gpg"
  if [[ "${USE_CN_MIRROR}" == "1" ]]; then
    docker_repo_url="https://mirrors.ustc.edu.cn/docker-ce/linux/debian"
    docker_gpg_url="https://mirrors.ustc.edu.cn/docker-ce/linux/debian/gpg"
  fi

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "${docker_gpg_url}" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] ${docker_repo_url} ${OS_CODENAME} stable
EOF

  apt_update

  log "安装 Docker Engine、Buildx 和 Compose 插件。"
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  run systemctl enable --now docker
}

install_nodejs() {
  [[ "${INSTALL_NODE}" == "1" ]] || return 0

  log "配置 NodeSource Node.js ${NODE_MAJOR}.x LTS 仓库。"

  install -m 0755 -d /etc/apt/keyrings

  rm -f /etc/apt/keyrings/nodesource.gpg
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --batch --yes --dearmor -o /etc/apt/keyrings/nodesource.gpg
  chmod a+r /etc/apt/keyrings/nodesource.gpg

  cat > /etc/apt/sources.list.d/nodesource.list <<EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main
EOF

  apt_update

  log "安装 Node.js 和 npm。"
  apt_install nodejs

  if command -v corepack >/dev/null 2>&1; then
    log "启用 Corepack，便于使用 pnpm/yarn。"
    run corepack enable
  else
    warn "未找到 corepack，已跳过 corepack enable。"
  fi

  if [[ "${USE_CN_MIRROR}" == "1" ]] && command -v npm >/dev/null 2>&1; then
    log "启用 npm 国内 registry。"
    run npm config set registry https://registry.npmmirror.com
  fi
}

configure_security() {
  [[ "${INSTALL_SECURITY}" == "1" ]] || return 0

  log "配置防火墙和基础安全服务。"

  apt_update
  apt_install ufw fail2ban unattended-upgrades chrony

  run ufw --force reset
  run ufw default deny incoming
  run ufw default allow outgoing
  run ufw allow "${SSH_PORT}/tcp"
  run ufw allow 80/tcp
  run ufw allow 443/tcp
  run ufw --force enable

  run systemctl enable --now fail2ban
  run systemctl enable --now chrony

  configure_unattended_upgrades
}

print_version_or_skip() {
  local title="$1"
  shift

  if "$@" >/tmp/init-server-version.out 2>&1; then
    printf '%-18s %s\n' "${title}：" "$(head -n 1 /tmp/init-server-version.out)"
  else
    printf '%-18s %s\n' "${title}：" "未安装或无法获取版本"
  fi
}

print_summary() {
  log "初始化完成，以下是环境摘要。"

  printf '\n%s\n' "==================== 服务器初始化摘要 ===================="
  printf '%-18s %s\n' "系统：" "${OS_PRETTY_NAME}"
  printf '%-18s %s\n' "架构：" "${ARCH}"
  printf '%-18s %s\n' "SSH 放行端口：" "${SSH_PORT}/tcp"
  print_version_or_skip "Docker" docker --version
  print_version_or_skip "Docker Compose" docker compose version
  print_version_or_skip "Node.js" node -v
  print_version_or_skip "npm" npm -v
  print_version_or_skip "Python" python3 --version
  print_version_or_skip "Nginx" nginx -v

  if command -v ufw >/dev/null 2>&1; then
    printf '\n%s\n' "UFW 状态："
    ufw status verbose || true
  else
    printf '\n%s\n' "UFW 状态：未安装或未配置"
  fi

  cat <<'EOF'

重要提醒：
1. 本脚本没有修改 SSH 配置，没有关闭密码登录，也没有关闭 root 登录。
2. Docker 与 UFW 同时使用时，Docker 发布到宿主机的容器端口可能绕过普通 UFW 规则；生产环境请按实际暴露端口额外加固。
3. 本脚本未安装 PostgreSQL、MySQL、Redis，未创建业务用户、业务目录、SSL 证书或站点配置。
4. 如果 USE_CN_MIRROR=1，Debian 源会被写入国内镜像配置；原源文件已保留备份。
===========================================================
EOF
}

main() {
  require_root
  load_os_info
  collect_interactive_choices
  configure_cn_apt_mirror
  install_base_packages
  install_repository_tools
  configure_locales
  install_nginx
  install_python_dev
  install_docker
  install_nodejs
  configure_security
  print_summary
}

main "$@"
