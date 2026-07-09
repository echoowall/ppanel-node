#!/bin/bash
#
# PPanel-node 一键安装脚本（origin 版：host 网络多 IP 源进源出，TCP/UDP）
# 二进制来自 fork 的滚动 Release：echoowall/ppanel-node @ origin-latest
#
# 用法：
#   bash <(curl -fsSL https://raw.githubusercontent.com/echoowall/ppanel-node/master/scripts/install-origin.sh) \
#        --api-host https://api.example.com --server-id 1 --secret-key xxxxx
#
# 更新：重新运行本脚本即可（拉最新 origin 版并保留现有 config.yml）。
#       ⚠️ 不要用 `ppnode update`——那会从官方仓库覆盖成非 origin 版。

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# 本 fork（改这里即可换成你自己的仓库）
FORK_REPO="echoowall/ppanel-node"
ASSET_TAG="latest"   # 滚动 release origin-latest 走 /releases/latest/download/

cur_dir=$(pwd)

[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用 root 用户运行此脚本！\n" && exit 1

# ---- OS 检测 ----
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif grep -Eqi "alpine" /etc/issue 2>/dev/null || grep -Eqi "alpine" /proc/version 2>/dev/null; then
    release="alpine"
elif grep -Eqi "debian" /etc/issue 2>/dev/null || grep -Eqi "debian" /proc/version 2>/dev/null; then
    release="debian"
elif grep -Eqi "ubuntu" /etc/issue 2>/dev/null || grep -Eqi "ubuntu" /proc/version 2>/dev/null; then
    release="ubuntu"
elif grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux" /etc/issue 2>/dev/null || grep -Eqi "centos|red hat|redhat" /proc/version 2>/dev/null; then
    release="centos"
elif grep -Eqi "arch" /proc/version 2>/dev/null; then
    release="arch"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

# ---- 参数解析 ----
API_HOST_ARG=""; SERVER_ID_ARG=""; SECRET_KEY_ARG=""
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --api-host)   API_HOST_ARG="$2"; shift 2 ;;
            --server-id)  SERVER_ID_ARG="$2"; shift 2 ;;
            --secret-key) SECRET_KEY_ARG="$2"; shift 2 ;;
            -h|--help)
                echo "用法: $0 [--api-host URL] [--server-id ID] [--secret-key KEY]"; exit 0 ;;
            *) shift ;;
        esac
    done
}

# ---- 架构映射（origin release 只有 amd64 / arm64）----
arch=$(uname -m)
if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64"
else
    echo -e "${red}origin 版仅提供 linux amd64 / arm64，当前架构：$(uname -m)${plain}"; exit 2
fi

install_base() {
    case "$release" in
        centos)
            rpm -q epel-release >/dev/null 2>&1 || yum install -y epel-release >/dev/null 2>&1
            yum install -y wget curl tar cronie socat ca-certificates >/dev/null 2>&1
            update-ca-trust force-enable >/dev/null 2>&1 || true ;;
        alpine)
            apk add --no-cache wget curl tar socat ca-certificates >/dev/null 2>&1
            update-ca-certificates >/dev/null 2>&1 || true ;;
        debian|ubuntu)
            apt-get update -y >/dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get install -y wget curl tar cron socat ca-certificates >/dev/null 2>&1
            update-ca-certificates >/dev/null 2>&1 || true ;;
        arch)
            pacman -Sy --noconfirm --needed wget curl tar cronie socat ca-certificates >/dev/null 2>&1 ;;
    esac
}

check_status() {
    if [[ ! -f /usr/local/PPanel-node/ppnode ]]; then return 2; fi
    if [[ x"${release}" == x"alpine" ]]; then
        [[ "$(service PPanel-node status 2>/dev/null | awk '{print $3}')" == "started" ]] && return 0 || return 1
    else
        [[ "$(systemctl is-active PPanel-node 2>/dev/null)" == "active" ]] && return 0 || return 1
    fi
}

generate_ppnode_config() {
    local api_host="$1" server_id="$2" secret_key="$3"
    mkdir -p /etc/PPanel-node >/dev/null 2>&1
    cat > /etc/PPanel-node/config.yml <<EOF
Log:
  Level: warn
  Output:
  Access: none

Api:
  # 后端 API 地址，例如 "https://api.example.com"
  ApiHost: ${api_host}
  # 服务器唯一标识
  ServerID: ${server_id}
  # 通讯密钥
  SecretKey: ${secret_key}
  Timeout: 30
EOF
    echo -e "${green}配置文件已生成，正在重启服务${plain}"
    if [[ x"${release}" == x"alpine" ]]; then service PPanel-node restart; else systemctl restart PPanel-node; fi
    sleep 2
    check_status && echo -e "${green}PPanel-node 启动成功${plain}" || echo -e "${red}启动可能失败，用 ppnode log 查看日志${plain}"
}

install_ppnode() {
    mkdir -p /usr/local/PPanel-node/
    cd /usr/local/PPanel-node/ || exit 1

    url="https://github.com/${FORK_REPO}/releases/${ASSET_TAG}/download/ppnode-linux-${arch}-origin.tar.gz"
    echo -e "${green}下载 origin 版（${arch}）：${url}${plain}"
    if ! curl -fL --progress-bar "$url" -o ppnode-origin.tar.gz; then
        echo -e "${red}下载失败，请确认服务器能访问 GitHub（或该 release 已发布）${plain}"; exit 1
    fi
    tar xzf ppnode-origin.tar.gz && rm -f ppnode-origin.tar.gz
    chmod +x ppnode
    mkdir -p /etc/PPanel-node/
    cp -f geoip.dat geosite.dat /etc/PPanel-node/ 2>/dev/null || true

    # systemd / openrc
    if [[ x"${release}" == x"alpine" ]]; then
        cat > /etc/init.d/PPanel-node <<'EOF'
#!/sbin/openrc-run
name="PPanel-node"
command="/usr/local/PPanel-node/ppnode"
command_args="server"
command_user="root"
pidfile="/run/ppnode.pid"
command_background="yes"
depend() { need net; }
EOF
        chmod +x /etc/init.d/PPanel-node
        rc-update add PPanel-node default >/dev/null 2>&1
    else
        cat > /etc/systemd/system/PPanel-node.service <<'EOF'
[Unit]
Description=PPanel-node Service (origin, source-in-source-out)
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=/usr/local/PPanel-node/
ExecStart=/usr/local/PPanel-node/ppnode server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable PPanel-node >/dev/null 2>&1
    fi
    echo -e "${green}PPanel-node (origin) 安装完成，已设置开机自启${plain}"

    # 装管理脚本（通用 start/stop/log 等；update 请勿使用，见结尾提示）
    curl -fsSL -o /usr/bin/ppnode https://raw.githubusercontent.com/perfect-panel/ppanel-node/master/scripts/ppnode.sh 2>/dev/null && chmod +x /usr/bin/ppnode

    # config：参数直给则生成并启动；已存在则保留（便于「重跑=更新」）；否则交互
    if [[ -n "$API_HOST_ARG" && -n "$SERVER_ID_ARG" && -n "$SECRET_KEY_ARG" ]]; then
        generate_ppnode_config "$API_HOST_ARG" "$SERVER_ID_ARG" "$SECRET_KEY_ARG"
    elif [[ -f /etc/PPanel-node/config.yml ]]; then
        echo -e "${green}检测到已有 config.yml，保留不变（本次仅更新二进制）${plain}"
        if [[ x"${release}" == x"alpine" ]]; then service PPanel-node restart; else systemctl restart PPanel-node; fi
        sleep 2
        check_status && echo -e "${green}PPanel-node 已重启${plain}" || echo -e "${red}重启可能失败，用 ppnode log 查看${plain}"
    else
        read -rp "首次安装，是否现在生成 config.yml？(y/n): " g
        if [[ "$g" =~ ^[Yy]$ ]]; then
            read -rp "面板 API 地址[https://example.com]: " api_host; api_host=${api_host:-https://example.com}
            read -rp "服务器 ID: " server_id; server_id=${server_id:-1}
            read -rp "通讯密钥: " secret_key
            generate_ppnode_config "$api_host" "$server_id" "$secret_key"
        else
            echo -e "${yellow}已跳过。稍后可执行 ppnode generate 生成配置${plain}"
        fi
    fi
}

print_footer() {
    echo "------------------------------------------"
    echo -e "${green}这是 origin 版：客户端连哪个本机 IP，出站就从哪个 IP 出（TCP/UDP）${plain}"
    echo "多 IP 上线前自检："
    echo "  ip -brief addr                 # 确认各 IP 已挂到网卡"
    echo "  ping -I <你的ip2> -c2 1.1.1.1  # 该 IP 能出站"
    echo "  sysctl net.ipv4.conf.all.rp_filter   # 建议 0 或 2，勿为 1"
    echo "------------------------------------------"
    echo -e "${yellow}更新：重新运行本脚本即可（保留 config，仅换最新 origin 二进制）${plain}"
    echo -e "${red}切勿使用 'ppnode update'——它会从官方仓库覆盖成非 origin 版！${plain}"
    echo "------------------------------------------"
    echo "常用：ppnode start|stop|restart|status|log|generate|uninstall"
}

parse_args "$@"
echo -e "${green}开始安装 PPanel-node (origin)${plain}"
install_base
install_ppnode
print_footer
cd "$cur_dir" || true
