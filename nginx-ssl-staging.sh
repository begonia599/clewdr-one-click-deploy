#!/bin/bash

# === 用户输入 ===
read -p "请输入你的域名（必填）: " DOMAIN
if [ -z "$DOMAIN" ]; then
    echo "域名不能为空，退出脚本。"
    exit 1
fi

read -p "请输入你的邮箱（用于证书通知，必填）: " EMAIL
if [ -z "$EMAIL" ]; then
    echo "邮箱不能为空，退出脚本。"
    exit 1
fi

read -p "请输入 Nginx 配置文件路径（必填，例如 /etc/nginx/sites-available/your_config）: " NGINX_CONFIG
if [ -z "$NGINX_CONFIG" ]; then
    echo "Nginx 配置文件路径不能为空，退出脚本。"
    exit 1
fi

echo "以下信息将用于 Staging 测试："
echo "域名: $DOMAIN"
echo "邮箱: $EMAIL"
echo "Nginx 配置文件: $NGINX_CONFIG"
read -p "确认无误吗？输入 y 继续，其他键退出: " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "已取消。"
    exit 1
fi

# === 安装 Certbot（如果未安装） ===
if ! command -v certbot &> /dev/null; then
    echo "检测到 Certbot 未安装，正在安装..."
    sudo apt update
    sudo apt install certbot python3-certbot-nginx -y
fi

# === 测试申请 SSL（Staging 环境） ===
echo "正在使用 Let's Encrypt Staging 环境申请测试证书..."
sudo certbot --nginx -d $DOMAIN --staging --non-interactive --agree-tos -m $EMAIL

# === 测试 Nginx 配置并重载 ===
sudo nginx -t && sudo systemctl reload nginx

# === 完成提示 ===
echo "Staging 测试证书申请完成！请访问 https://$DOMAIN 验证。"
echo "注意：浏览器会提示证书不受信任，因为这是测试证书。"
