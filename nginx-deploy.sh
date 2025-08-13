#!/bin/bash

# === 用户输入 ===
read -p "请输入域名或服务器IP（必填）: " SERVER_NAME
if [ -z "$SERVER_NAME" ]; then
    echo "域名或IP不能为空，退出脚本。"
    exit 1
fi

read -p "请输入后端服务端口（必填）: " BACKEND_PORT
if [ -z "$BACKEND_PORT" ]; then
    echo "后端服务端口不能为空，退出脚本。"
    exit 1
fi

# 配置文件名
CONFIG_NAME="${SERVER_NAME//./_}"   # 将 . 替换为 _ 用作文件名
CONFIG_PATH="/etc/nginx/sites-available/$CONFIG_NAME"

# === 安装 Nginx（如果未安装） ===
if ! command -v nginx &> /dev/null; then
    echo "检测到 Nginx 未安装，正在安装..."
    sudo apt update
    sudo apt install nginx -y
fi

# === 生成 Nginx 配置 ===
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

# === 启用站点 ===
if [ ! -f "/etc/nginx/sites-enabled/$CONFIG_NAME" ]; then
    sudo ln -s "$CONFIG_PATH" "/etc/nginx/sites-enabled/"
fi

# === 测试配置并重载 Nginx ===
sudo nginx -t && sudo systemctl reload nginx

# === 完成提示 ===
echo "配置完成！请确认 DNS 已解析到服务器IP，并尝试访问: http://$SERVER_NAME"
