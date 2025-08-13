#!/bin/bash

set -e

echo "==============================================="
echo "=== 步骤 1: 检查并安装 Docker ==="
echo "==============================================="
if systemctl is-active --quiet docker; then
    echo ">> 已检测到 Docker，跳过安装。"
else
    echo ">> 未检测到 Docker，开始安装..."
    sudo apt update
    sudo apt upgrade -y
    if sudo curl -fsSL https://get.docker.com | bash; then
        echo "Docker 从官方源安装成功。"
    else
        echo "警告：官方安装失败，尝试备用镜像..."
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

    echo ">> 检查 docker compose 插件..."
    if ! docker compose version &> /dev/null; then
        echo "错误：'docker compose' 命令未检测到。"
        exit 1
    fi
    echo "docker compose 版本: $(docker compose version)"

    echo ">> 将当前用户添加到 docker 组..."
    sudo usermod -aG docker "$USER"
    echo "Docker 安装完成！为使权限生效，请重新登录服务器。"
    echo "请重新连接后，再次运行此脚本以继续后续部署。"
    exit 0
fi

echo "==============================================="
echo "=== 步骤 2: 部署 Clewdr 服务并收集所有配置 ==="
echo "==============================================="

read -p "请输入 API 密钥 (password)，留空则为空: " API_PASSWORD
read -p "请输入前端管理密码 (admin_password)，留空则为空: " ADMIN_PASSWORD
read -p "请输入代理 proxy，留空则为空: " PROXY

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

echo ""
echo ">>>>> 域名与备案确认 <<<<<"
echo "根据中国大陆的法律法规，如果您的服务器位于中国大陆，域名必须备案才能通过 80/443 端口访问。"
echo "如果没有备案，我们将通过服务器公网IP进行部署，并跳过HTTPS配置。"
echo ""
read -p "如果您的服务器在中国大陆，域名已完成备案？ (y/n): " HAS_ICP

SERVER_NAME=""
if [[ "$HAS_ICP" =~ ^[yY]$ ]]; then
    read -p "请输入您要配置的域名（必填，例如：example.com）: " SERVER_NAME
    if [ -z "$SERVER_NAME" ]; then
        echo "域名不能为空，退出脚本。"
        exit 1
    fi
    echo ""
    echo ">>>>> SSL 证书选项 <<<<<"
    read -p "是否需要自动申请新的 SSL 证书？(y/n, 选n将使用已有的备份证书) : " AUTO_CERT
    
    if [[ "$AUTO_CERT" =~ ^[yY]$ ]]; then
        read -p "请输入您的邮箱（用于接收续订通知，必填）: " EMAIL
        if [ -z "$EMAIL" ]; then
            echo "邮箱不能为空，退出脚本。"
            exit 1
        fi
        echo "请选择证书申请环境："
        echo "1) 正式环境 (推荐，将申请真实证书)"
        echo "2) 测试环境 (dry-run，用于测试配置，不会消耗申请次数)"
        read -p "请输入您的选择 (1 或 2): " CHOICE
    else
        read -p "请确保您已将证书备份文件上传到服务器的home目录下。请输入文件名（例如：clewdr_ssl_backup.tar.gz）: " CERT_FILE
        if [ -z "$CERT_FILE" ]; then
            echo "文件名不能为空，退出脚本。"
            exit 1
        fi
    fi
else
    echo "您选择了不使用域名或未备案域名。Nginx 将配置为通过服务器IP访问。"
    echo "请确保您服务器的80端口在防火墙或安全组中是开放的。"
fi


sudo mkdir -p /etc/clewdr
cd /etc/clewdr || exit

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

echo "==============================================="
echo "=== 步骤 3: 部署 Nginx 并配置 HTTP 代理 ==="
echo "==============================================="
BACKEND_PORT=$PORT
CONFIG_NAME="clewdr_http"
CONFIG_PATH="/etc/nginx/sites-available/$CONFIG_NAME"

if ! command -v nginx &> /dev/null; then
    echo "检测到 Nginx 未安装，正在安装..."
    sudo apt update
    sudo apt install nginx -y
fi

echo "正在生成 Nginx 配置文件: $CONFIG_PATH"
if [[ "$HAS_ICP" =~ ^[yY]$ ]]; then
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
else
    sudo tee "$CONFIG_PATH" > /dev/null <<EOF
server {
    listen 80 default_server;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:$BACKEND_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
fi

if [ ! -f "/etc/nginx/sites-enabled/$CONFIG_NAME" ]; then
    sudo ln -s "$CONFIG_PATH" "/etc/nginx/sites-enabled/"
fi

sudo nginx -t && sudo systemctl reload nginx

echo "Nginx HTTP 代理配置完成！请确认防火墙已放行80端口，并尝试访问: http://$SERVER_NAME"


if [[ "$HAS_ICP" =~ ^[yY]$ ]]; then
    echo "==============================================="
    echo "=== 步骤 4: 申请 SSL 证书或使用已有证书 ==="
    echo "==============================================="
    
    if [[ "$AUTO_CERT" =~ ^[yY]$ ]]; then
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
        eval "$CERTBOT_CMD"
        
        if [ $? -eq 0 ]; then
            echo "恭喜！HTTPS 已成功配置在 https://$SERVER_NAME"
            echo "证书已部署，Nginx 已重载。"
        else
            echo "证书申请或配置失败，请检查 /var/log/letsencrypt/letsencrypt.log 获取更多信息。"
        fi

    else
        echo ">> 您选择了使用已有的证书。"
        
        CERT_PATH="$HOME/$CERT_FILE"
        if [ ! -f "$CERT_PATH" ]; then
            echo "错误：未找到文件 $CERT_PATH，请检查文件名和路径。"
            exit 1
        fi
        
        echo "正在解压证书文件..."
        sudo tar -xzvf "$CERT_PATH" -C /
        
        if [ $? -eq 0 ]; then
            echo "证书文件已成功解压到 /etc/letsencrypt/live/ 目录。"
            
            echo "正在配置 Nginx 以启用 HTTPS..."
            if ! command -v certbot &> /dev/null; then
                echo "检测到 Certbot 未安装，正在安装..."
                sudo apt update
                sudo apt install certbot python3-certbot-nginx -y
            fi
            
            sudo certbot --nginx -d "$SERVER_NAME" --email your-email@example.com --agree-tos --no-eff-email --redirect --dry-run
            
            sudo nginx -t && sudo systemctl reload nginx
            
            echo "==========================================================="
            echo "恭喜！HTTPS 已成功配置在 https://$SERVER_NAME"
            echo "脚本已尝试配置自动续签。您可以通过运行 'sudo certbot renew --dry-run' 来验证。"
            echo "==========================================================="
        else
            echo "证书文件解压失败，请检查文件是否损坏。"
            exit 1
        fi
    fi
else
    echo "==============================================="
    echo "=== 已跳过 HTTPS 配置 ==="
    echo "==============================================="
fi

echo "==============================================="
echo "=== 脚本全部执行完毕 ==="
echo "==============================================="