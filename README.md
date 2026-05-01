# debian-initiator
# Debian 服务器中文初始化脚本

`init_debian_server.sh` 是一个面向 Debian 11/12/13 的服务器初始化脚本，适合新装或接近新装的 Web 通用服务器、容器宿主机和开发构建环境。

脚本使用中文交互提示，默认安装常用运维工具、Nginx、Docker、Node.js、Python 开发环境，并配置 UFW、Fail2ban、自动安全更新等基础安全项。

## 支持系统

- Debian 11 Bullseye
- Debian 12 Bookworm
- Debian 13 Trixie

不支持 Ubuntu、CentOS、AlmaLinux、Rocky Linux 等非 Debian 系统。

## 快速使用

上传脚本到服务器后执行：

```bash
sudo bash init_debian_server.sh
```

脚本会进入中文交互向导，逐项询问是否安装：

- 中国大陆镜像源
- 基础运维工具
- Nginx
- Docker Engine + Docker Compose 插件
- Node.js + npm
- Python 开发环境
- UFW、Fail2ban、自动安全更新
- UFW 需要放行的 SSH 端口

直接回车会使用推荐默认值。

> 建议使用 `sudo bash init_debian_server.sh` 执行。脚本已经兼容误用 `sh init_debian_server.sh` 的情况，但 Bash 仍然是推荐方式。

## 语法检查

执行前可以先检查语法：

```bash
bash -n init_debian_server.sh
```

没有输出通常表示语法检查通过。

## 非交互执行

如果用于自动化部署，可以关闭交互模式：

```bash
sudo INTERACTIVE=0 bash init_debian_server.sh
```

也可以通过环境变量控制安装项：

```bash
sudo INTERACTIVE=0 USE_CN_MIRROR=1 INSTALL_NODE=0 bash init_debian_server.sh
```

## 配置项

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `INTERACTIVE` | `1` | 是否启用交互向导；设为 `0` 时使用环境变量或默认值直接执行 |
| `USE_CN_MIRROR` | `0` | 是否启用中国大陆镜像源 |
| `SSH_PORT` | `22` | UFW 放行的 SSH 端口；不会修改 SSH 服务配置 |
| `NODE_MAJOR` | `24` | 安装的 Node.js 主版本 |
| `INSTALL_BASE_TOOLS` | `1` | 是否安装基础运维工具 |
| `INSTALL_SECURITY` | `1` | 是否配置 UFW、Fail2ban、自动安全更新 |
| `INSTALL_DOCKER` | `1` | 是否安装 Docker Engine 和 Compose 插件 |
| `INSTALL_NODE` | `1` | 是否安装 Node.js 和 npm |
| `INSTALL_NGINX` | `1` | 是否安装并启用 Nginx |
| `INSTALL_PYTHON_DEV` | `1` | 是否安装 Python 开发环境 |

变量值使用 `1` 表示启用，`0` 表示禁用。

## 常见示例

启用国内镜像并使用默认安装项：

```bash
sudo USE_CN_MIRROR=1 bash init_debian_server.sh
```

只安装基础工具、安全配置和 Docker，不安装 Nginx、Node.js、Python 开发环境：

```bash
sudo INTERACTIVE=0 INSTALL_NGINX=0 INSTALL_NODE=0 INSTALL_PYTHON_DEV=0 bash init_debian_server.sh
```

安装 Node.js 22：

```bash
sudo NODE_MAJOR=22 bash init_debian_server.sh
```

SSH 使用 2222 端口时，让 UFW 放行 2222：

```bash
sudo SSH_PORT=2222 bash init_debian_server.sh
```

注意：这只会配置 UFW 放行端口，不会修改 `/etc/ssh/sshd_config`。

## 默认安装内容

基础运维工具：

- `curl`、`wget`、`git`
- `vim`、`nano`
- `htop`、`btop`、`tmux`
- `unzip`、`zip`、`tar`
- `jq`、`rsync`
- `dnsutils`、`net-tools`、`iproute2`
- `ca-certificates`、`gnupg`、`lsb-release`
- `locales`、`build-essential`

Web 和运行时：

- Nginx
- Docker Engine
- Docker Buildx 插件
- Docker Compose 插件
- Node.js + npm
- Corepack
- Python 3、pip、venv、pipx

安全和系统服务：

- UFW
- Fail2ban
- unattended-upgrades
- Chrony

## 镜像源说明

默认 `USE_CN_MIRROR=0`，不会替换系统 apt 源。

当 `USE_CN_MIRROR=1` 时：

- Debian apt 源会写入 `/etc/apt/sources.list.d/debian-cn.sources`
- 原始源文件会备份到 `/etc/apt/backup-before-init-时间戳/`
- Docker 源会使用中国科学技术大学镜像
- npm registry 会设置为 `https://registry.npmmirror.com`

## 安全说明

脚本默认会配置 UFW：

- 默认拒绝入站连接
- 默认允许出站连接
- 放行 SSH 端口
- 放行 `80/tcp`
- 放行 `443/tcp`

脚本不会做这些操作：

- 不修改 SSH 端口
- 不关闭 root 登录
- 不关闭密码登录
- 不创建业务用户
- 不创建业务目录
- 不申请或配置 SSL 证书
- 不生成 Nginx 业务站点配置
- 不安装 PostgreSQL、MySQL、Redis

## Docker 与 UFW 提醒

Docker 与 UFW 同时使用时，Docker 发布到宿主机的容器端口可能绕过普通 UFW 规则。

生产环境请按实际暴露端口进一步加固防火墙策略，尤其是数据库、Redis、管理后台等服务不要直接暴露到公网。

## 执行后检查

初始化完成后可以检查：

```bash
docker --version
docker compose version
node -v
npm -v
python3 --version
nginx -v
ufw status verbose
systemctl is-active nginx docker fail2ban chrony
```

如果某个组件在交互中选择了不安装，对应命令不存在是正常情况。

## 重复执行

脚本按可重复执行设计：

- 已存在的软件包会由 apt 自动跳过
- Docker、NodeSource 源文件会覆盖写入
- 服务启用使用 `systemctl enable --now`
- 国内镜像启用时会备份原 apt 源

如果服务器已经运行生产业务，执行前请先确认防火墙和服务变更不会影响现有访问。
