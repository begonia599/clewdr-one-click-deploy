#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- 1. Docker One-Click Installation ---
echo "==============================================="
echo "=== 步骤 1: 检查并安装 Docker ==="
echo "==============================================="

# Check if Docker is already installed
if command -v docker &> /dev/null; then
    echo ">> 已检测到 Docker，跳过安装。"
else
    echo ">> 未检测到 Docker，开始安装..."
    # Update system dependencies
    echo ">> 更新系统依赖..."
    sudo apt update
    sudo apt upgrade -y

    # Install Docker (Official source first, with fallback mirrors)
    echo ">> 正在安装 Docker (官方源，含备用镜像)..."
    if sudo curl -fsSL https://get.docker.com | bash; then
        echo "Docker 从官方源安装成功。"
    else
        echo "警告：官方安装失败，尝试备用镜像..."
        # Fallback logic from your Docker script
        if sudo curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun; then
            echo "Docker 从阿里云镜像安装成功。"
        else
            echo "警告：阿里云镜像失败，尝试 GitHub 镜像..."
            if sudo curl -fsSL https://github.com/tech-shrimp/docker_installer/releases/download/latest/linux.sh | bash -s docker --mirror Aliyun; then
                echo "Docker 从 GitHub 镜像安装成功。"
            else
                echo "警告：GitHub 镜像失败，尝试 Gitee 镜像..."
                if sudo curl -fsSL https://gitee.com/tech-shrimp/docker_installer/releases/download/latest/linux.sh | bash -s docker --mirror Aliyun; then
                    echo "Docker 从 Gitee 镜像安装成功。"
                else
                    echo "错误：Docker 安装失败。请检查网络连接或手动安装。"
                    exit 1
                fi
            fi
        fi
    fi

    # Check Docker compose command
    echo ">> 检查 docker compose 插件..."
    if ! docker compose version &> /dev/null; then
        echo "错误：'docker compose' 命令未检测到。这可能表明 Docker 安装不完整。"
        exit 1
    fi
    echo "docker compose 版本: $(docker compose version)"

    # Add user permissions
    echo ">> 将当前用户添加到 docker 组..."
    sudo usermod -aG docker $USER
    echo "Docker 安装完成！为使权限生效，请重新登录服务器。"
    echo "请重新连接后，再次运行此脚本以继续后续部署。"
    exit 0 # Exit after new installation to enforce re-login
fi

# --- 2. Deploy Clewdr ---
echo "==============================================="
echo "=== 步骤 2: 部署 Clewdr 服务 ==="
echo "==============================================="
sudo mkdir -p /etc/clewdr
cd /etc/clewdr || exit

read -p "请输入 API 密钥 (password)，留空默认空: " API_PASSWORD
read -p "请输入前端管理密码 (admin_password)，留空默认空: " ADMIN_PASSWORD
read -p "请输入代理 proxy，留空默认空: " PROXY

PORT=8484
MAX_RETRIES=5

cookie_array=()
while true; do
  read -p "请输入 Claude Pro Cookie（留空结束）: " COOKIE
  [[ -z "$COOKIE" ]] && break
  cookie_array+=("$COOKIE")
done

gemini_keys=()
while true; do
  read -p "请输入 Gemini API Key（留空结束）: " GEMINI
  [[ -z "$GEMINI" ]] && break
  gemini_keys+=("$GEMINI")
done

cat <<EOL | sudo tee clewdr.toml >/dev/null
wasted_cookie = []
ip = "0.0.0.0"
port = $PORT
check_update = true
auto_update = false
password = "$API_PASSWORD"
admin_password = "$ADMIN_PASSWORD"
proxy = "$PROXY"
max_retries = $MAX_RETRIES
preserve_chats = false
web_search = false
cache_response = 0
not_hash_system = false
not_hash_last_n = 0
skip_first_warning = false
skip_second_warning = false
skip_restricted = false
skip_non_pro = false
skip_rate_limit = true
skip_normal_pro = false
use_real_roles = true
custom_prompt = ""
padtxt_len = 4000

[vertex]
EOL

for cookie in "${cookie_array[@]}"; do
  echo "[[cookie_array]]" | sudo tee -a clewdr.toml >/dev/null
  echo "cookie = \"$cookie\"" | sudo tee -a clewdr.toml >/dev/null
done

for key in "${gemini_keys[@]}"; do
  echo "[[gemini_keys]]" | sudo tee -a clewdr.toml >/dev/null
  echo "key = \"$key\"" | sudo tee -a clewdr.toml >/dev/null
done

cat <<EOL | sudo tee docker-compose.yml >/dev/null
services:
  clewdr:
    image: ghcr.io/xerxes-2/clewdr:latest
    container_name: clewdr
    hostname: clewdr
    volumes:
      - ./clewdr.toml:/app/clewdr.toml
    network_mode: host
    restart: unless-stopped
EOL

sudo docker compose up -d

echo "Clewdr 部署完成！"
sudo docker ps | grep clewdr
echo "可用日志查看： sudo docker logs -f clewdr"
cd - > /dev/null

# --- 3. Deploy Nginx ---
echo "==============================================="
echo "=== 步骤 3: 部署 Nginx 并配置 HTTP 代理 ==="
echo "==============================================="
read -p "请输入域名或服务器IP（必填）: " SERVER_NAME
if [ -z "$SERVER_NAME" ]; then
    echo "域名或IP不能为空，退出脚本。"
    exit 1
fi

BACKEND_PORT=8484
CONFIG_NAME="${SERVER_NAME//./_}"
CONFIG_PATH="/etc/nginx/sites-available/$CONFIG_NAME"

if ! command -v nginx &> /dev/null; then
    echo "检测到 Nginx 未安装，正在安装..."
    sudo apt update
    sudo apt install nginx -y
fi

echo "正在生成 Nginx 配置文件: $CONFIG_PATH"
sudo tee "$CONFIG_PATH" > /dev/null <<EOF
server {
    listen 80;
    server_name $SERVER_NAME;

    location / {
        proxy_pass http://127.0.0.1:$BACKEND_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

if [ ! -f "/etc/nginx/sites-enabled/$CONFIG_NAME" ]; then
    sudo ln -s "$CONFIG_PATH" "/etc/nginx/sites-enabled/"
fi

sudo nginx -t && sudo systemctl reload nginx

echo "Nginx HTTP 代理配置完成！请确认 DNS 已解析到服务器IP，并尝试访问: http://$SERVER_NAME"

# --- 4. Deploy HTTPS ---
echo "==============================================="
echo "=== 步骤 4: 申请 SSL 证书并配置 HTTPS ==="
echo "==============================================="
read -p "请输入您的邮箱（用于接收续订通知，必填）: " EMAIL
if [ -z "$EMAIL" ]; then
    echo "邮箱不能为空，退出脚本。"
    exit 1
fi

echo "请选择证书申请环境："
echo "1) 正式环境 (推荐，将申请真实证书)"
echo "2) 测试环境 (dry-run，用于测试配置，不会消耗申请次数)"
read -p "请输入您的选择 (1 或 2): " CHOICE

CERTBOT_CMD=""
case $CHOICE in
    1)
        echo "您选择了正式环境。"
        CERTBOT_CMD="sudo certbot --nginx -d "$SERVER_NAME" --email "$EMAIL" --agree-tos --no-eff-email"
        ;;
    2)
        echo "您选择了测试环境。"
        CERTBOT_CMD="sudo certbot certonly --nginx --dry-run -d "$SERVER_NAME" --email "$EMAIL" --agree-tos --no-eff-email"
        ;;
    *)
        echo "无效的选择，退出脚本。"
        exit 1
        ;;
esac

if ! command -v certbot &> /dev/null; then
    echo "检测到 Certbot 未安装，正在安装..."
    sudo apt update
    sudo apt install certbot python3-certbot-nginx -y
fi

echo "正在为 $SERVER_NAME 申请 SSL 证书..."
eval $CERTBOT_CMD

if [ $? -eq 0 ]; then
    echo "==========================================================="
    if [ "$CHOICE" == "1" ]; then
        echo "恭喜！HTTPS 已成功配置在 https://$SERVER_NAME"
        echo "证书已部署，Nginx 已重载。"
    else
        echo "证书测试申请成功！您的配置没有问题。"
        echo "如果您希望申请真实证书，请再次运行此脚本并选择正式环境。"
    fi
    echo "==========================================================="
else
    echo "证书申请或配置失败，请检查 /var/log/letsencrypt/letsencrypt.log 获取更多信息。"
fi

echo "==============================================="
echo "=== 脚本全部执行完毕 ==="
echo "==============================================="