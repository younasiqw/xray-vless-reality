#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# 配置文件路径
CONFIG_FILE="/usr/local/etc/xray/config.json"

# 检查 root 权限
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：${PLAIN} 必须使用 root 用户运行此脚本！\n" && exit 1

# 检查系统
if [[ -f /usr/bin/apt ]]; then
    CMD_INSTALL="apt install -y"
elif [[ -f /usr/bin/yum ]]; then
    CMD_INSTALL="yum install -y"
else
    echo -e "${RED}错误：${PLAIN} 系统不受支持，请使用 Debian/Ubuntu/CentOS！"
    exit 1
fi

show_menu() {
    clear
    echo -e "${BLUE}  ███▄ ▄███▓ ██▀███   ██░ ██  ▒█████   ██ ▄█▀ █    ██   ██████  ▄▄▄       ██▓ "
    echo -e " ▓██▒▀█▀ ██▒▓██ ▒ ██▒▓██░ ██▒▒██▒  ██▒ ██▄█▒  ██  ▓██▒▒██    ▒ ▒████▄    ▓██▒ "
    echo -e " ▓██    ▓██░▓██ ░▄█ ▒▒██▀▀██░▒██░  ██▒▓███▄░ ▓██  ▒██░░ ▓██▄   ▒██  ▀█▄  ▒██▒ "
    echo -e " ▒██    ▒██ ▒██▀▀█▄  ░▓█ ░██ ▒██   ██░▓██ █▄ ▓▓█  ░██░  ▒   ██▒░██▄▄▄▄██ ░██░ "
    echo -e " ▒██▒   ░██▒░██▓ ▒██▒░▓█▒░██▓░ ████▓▒░▒██▒ █▄▒▒█████▓ ▒██████▒▒ ▓█   ▓██▒░██░ "
    echo -e " ░ ▒░   ░  ░░ ▒▓ ░▒▓░ ▒ ░░▒░▒░ ▒░▒░▒░ ▒ ▒▒ ▓▒░▒▓▒ ▒ ▒ ▒ ▒▓▒ ▒ ░ ▒▒   ▓▒█░░▓   "
    echo -e " ░  ░      ░  ░▒ ░ ▒░ ▒ ░▒░ ░  ░ ▒ ▒░ ░ ░▒ ▒░░░▒░ ░ ░ ░ ░▒  ░ ░  ▒   ▒▒ ░ ▒ ░ "
    echo -e " ░      ░     ░░   ░  ░  ░░ ░░ ░ ░ ▒  ░ ░░ ░  ░░░ ░ ░ ░  ░  ░    ░   ▒    ▒ ░ "
    echo -e "        ░      ░      ░  ░  ░    ░ ░  ░  ░      ░            ░       ░  ░ ░   ${PLAIN}"
    echo -e "--------------------------------------------------------------------------------"
    echo -e "  ${GREEN}1.${PLAIN} 安装 REALITY"
    echo -e "  ${GREEN}2.${PLAIN} 卸载 REALITY"
    echo -e "  ${GREEN}3.${PLAIN} 添加 Socks5 节点分流"
    echo -e "  ${GREEN}4.${PLAIN} 显示分享 URL"
    echo -e "  ${GREEN}0.${PLAIN} 退出脚本"
    echo -e "--------------------------------------------------------------------------------"
    read -p "请输入选项 [0-4]: " choice
}

install_dependencies() {
    $CMD_INSTALL curl wget jq openssl tar
}

# 【修复挂起卡死的核心】：增加 -m 5 (最大等待 5 秒)，防止没有 IPv6 的机器无限卡死
get_ip() {
    ipv4=$(curl -s -m 5 https://v4.ident.me)
    ipv6=$(curl -s -m 5 https://v6.ident.me)
}

install_xray() {
    latest_version=$(curl -s -m 5 https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
    echo -e "检测到 Xray 最新版本为: ${GREEN}${latest_version}${PLAIN}"
    read -p "直接回车安装最新版，或输入版本号 (例如 v26.3.27): " input_version
    version=${input_version:-$latest_version}

    echo -e "正在安装 Xray $version..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --version "$version"
}

config_reality() {
    get_ip
    echo -e "\n--- IP 选择 ---"
    echo -e "1. IPv4: ${ipv4}"
    echo -e "2. IPv6: ${ipv6}"
    read -p "选择安装 IP 类型 (默认 1): " ip_choice
    if [[ "$ip_choice" == "2" ]]; then
        server_ip=$ipv6
    else
        server_ip=$ipv4
    fi

    read -p "请输入监听端口 (默认 443): " port
    port=${port:-443}

    # UUID
    auto_uuid=$(/usr/local/bin/xray uuid)
    read -p "请输入 UUID (回车自动生成: $auto_uuid): " uuid
    uuid=${uuid:-$auto_uuid}

    # Keys (根据手动调试信息完美适配)
    read -p "请输入私钥 (回车自动生成): " input_pk
    
    if [[ -z "$input_pk" ]]; then
        # 自动生成：使用 Xray 原生逻辑，直接抓取最后一段字符串
        key_pair=$(/usr/local/bin/xray x25519)
        pk=$(echo "$key_pair" | awk '/Private/ {print $NF}' | tr -dc 'A-Za-z0-9-_')
        pbk=$(echo "$key_pair" | awk '/Public/ {print $NF}' | tr -dc 'A-Za-z0-9-_')
    else
        # 手动输入：用 printf 安全剥离手滑复制进来的 \r 和空格
        pk=$(printf "%s" "$input_pk" | tr -dc 'A-Za-z0-9-_')
        
        # 抛弃 grep，直接用 awk 匹配包含 Public 的行，提取最后一个字段，解决格式差异
        pbk=$(/usr/local/bin/xray x25519 -i "$pk" 2>/dev/null | awk '/Public/ {print $NF}' | tr -dc 'A-Za-z0-9-_')
        
        # 容错：如果用户输入的私钥根本不对，给出提示
        if [[ -z "$pbk" ]]; then
            echo -e "${RED}错误：私钥格式无效，Xray 无法推导公钥！请检查输入。${PLAIN}"
            exit 1
        fi
    fi

    # ShortID
    auto_sid=$(openssl rand -hex 8)
    read -p "请输入 ShortID (回车随机生成: $auto_sid): " sid
    sid=${sid:-$auto_sid}

    # Fingerprint
    echo -e "\n--- 选择 Fingerprint (指纹) ---"
    fp_list=("chrome" "firefox" "safari" "ios" "android" "edge" "360" "qq" "random" "randomized")
    for i in "${!fp_list[@]}"; do echo -e "$((i+1)). ${fp_list[$i]}"; done
    read -p "选择编号 (默认 1): " fp_idx
    if [[ -z "$fp_idx" ]]; then
        fp="chrome"
    else
        fp=${fp_list[$((fp_idx-1))]:-chrome}
    fi

    # Dest
    read -p "请输入目标网站域名 (例如 www.microsoft.com): " dest_site
    read -p "请输入目标网站端口 (默认 443): " dest_port
    dest_port=${dest_port:-443}

    # 生成配置
    mkdir -p /usr/local/etc/xray
    cat <<EOF > $CONFIG_FILE
{
    "log": { "loglevel": "warning" },
    "inbounds": [
        {
            "port": $port,
            "protocol": "vless",
            "settings": {
                "clients": [{ "id": "$uuid", "flow": "xtls-rprx-vision" }],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "$dest_site:$dest_port",
                    "xver": 0,
                    "serverNames": ["$dest_site"],
                    "privateKey": "$pk",
                    "shortIds": ["$sid"]
                }
            }
        }
    ],
    "outbounds": [
        { "protocol": "freedom", "tag": "direct" },
        { "protocol": "blackhole", "tag": "blocked" }
    ],
    "routing": {
        "domainStrategy": "AsIs",
        "rules": []
    }
}
EOF
    systemctl restart xray
    echo -e "${GREEN}REALITY 安装完成并已启动！${PLAIN}"
    show_info "$fp"
}

show_info() {
    if [[ ! -f $CONFIG_FILE ]]; then
        echo -e "${RED}错误：${PLAIN} 未检测到 Xray 配置文件。"
        return
    fi
    
    local fp_used=${1:-chrome}

    # 提取信息
    port=$(jq -r '.inbounds[0].port' $CONFIG_FILE)
    uuid=$(jq -r '.inbounds[0].settings.clients[0].id' $CONFIG_FILE)
    flow=$(jq -r '.inbounds[0].settings.clients[0].flow' $CONFIG_FILE)
    sni=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' $CONFIG_FILE)
    raw_pk=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' $CONFIG_FILE)
    sid=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' $CONFIG_FILE)
    
    # 【核心修复】：将 jq 提取的私钥强行洗净，彻底干掉附着的 \r 和杂乱字符
    pk=$(printf "%s" "$raw_pk" | tr -dc 'A-Za-z0-9-_')

    # 动态获取 IP
    if [[ -z "$server_ip" ]]; then
        get_ip
        server_ip=${ipv4:-$ipv6}
    fi

    # 【核心修复】：使用 awk 直接匹配 'Public' 行并打印最后一列 ($NF)，无视它叫 Password 还是 PublicKey
    pbk_display=$(/usr/local/bin/xray x25519 -i "$pk" 2>/dev/null | awk '/Public/ {print $NF}' | tr -dc 'A-Za-z0-9-_')

    echo -e "\n${YELLOW}--- REALITY 配置信息 ---${PLAIN}"
    echo -e "服务器 IP  : ${server_ip}"
    echo -e "监听端口   : $port"
    echo -e "UUID       : $uuid"
    echo -e "流控 (flow): $flow"
    echo -e "目标网站   : $sni"
    echo -e "公钥 (pbk) : ${GREEN}$pbk_display${PLAIN}"
    echo -e "私钥 (pk)  : $pk"
    echo -e "ShortID    : $sid"
    
    # 拼接 URL
    url="vless://$uuid@${server_ip}:$port?security=reality&sni=$sni&fp=$fp_used&pbk=$pbk_display&sid=$sid&type=tcp&flow=$flow#REALITY_$(hostname)"
    echo -e "\n${GREEN}分享链接 (URL):${PLAIN}\n${BLUE}$url${PLAIN}"
}

add_s5_outbound() {
    if [[ ! -f $CONFIG_FILE ]]; then echo -e "${RED}错误：请先安装 REALITY！${PLAIN}"; return; fi

    read -p "请输入 Socks5 服务器 IP/域名: " s5_ip
    read -p "请输入 Socks5 端口: " s5_port
    read -p "请输入用户名 (留空则无): " s5_user
    read -p "请输入密码 (留空则无): " s5_pass
    read -p "请输入要分流的网站域名 (默认 netflix.com, 多个用逗号隔开): " s5_domains
    s5_domains=${s5_domains:-"netflix.com,netflix.net,nflximg.net,nflxvideo.net,nflxso.net,nflxext.com"}

    # 使用 jq 更新配置
    s5_outbound=$(cat <<EOF
{
    "protocol": "socks",
    "tag": "socks5-out",
    "settings": {
        "servers": [{
            "address": "$s5_ip",
            "port": $s5_port,
            "users": $([[ -n "$s5_user" ]] && echo "[{\"user\": \"$s5_user\", \"pass\": \"$s5_pass\"}]" || echo "[]")
        }]
    }
}
EOF
)
    s5_rule=$(cat <<EOF
{
    "type": "field",
    "outboundTag": "socks5-out",
    "domain": [$(echo $s5_domains | sed 's/,/", "/g' | sed 's/^/"/' | sed 's/$/"/')]
}
EOF
)

    tmp_config=$(mktemp)
    jq ".outbounds += [$s5_outbound] | .routing.rules = [$s5_rule] + .routing.rules" $CONFIG_FILE > "$tmp_config" && mv "$tmp_config" $CONFIG_FILE
    
    systemctl restart xray
    echo -e "${GREEN}Socks5 分流配置已添加并重启服务！${PLAIN}"
}

uninstall_xray() {
    read -p "确定要卸载 Xray 吗？[y/N]: " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove
        rm -rf /usr/local/etc/xray
        echo -e "${GREEN}卸载完成。${PLAIN}"
    fi
}

# 主循环
install_dependencies
while true; do
    show_menu
    case $choice in
        1)
            install_xray
            config_reality
            ;;
        2)
            uninstall_xray
            ;;
        3)
            add_s5_outbound
            ;;
        4)
            # 在选项4中，如果在 show_info 里 server_ip 是空的它会自动调用一次 get_ip，
            # 没必要在这里也调用一次，这里可以直接清掉前面的 get_ip 以提升响应速度
            show_info
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请重新选择${PLAIN}"
            ;;
    esac
    read -p "按回车键返回菜单..."
done
