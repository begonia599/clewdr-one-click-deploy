#!/bin/bash

# === 用户输入 ===
read -p "请输入您要配置 HTTPS 的域名（必填）: " DOMAIN
if [ -z "$DOMAIN" ]; then
    echo "域名不能为空，退出脚本。"
    exit 1
fi

read -p "请输入您的邮箱（用于接收续订通知，必填）: " EMAIL
if [ -z "$EMAIL" ]; then
    echo "邮箱不能为空，退出脚本。"
    exit 1
fi

# 询问用户选择正式环境还是测试环境
echo "请选择证书申请环境："
echo "1) 正式环境 (推荐，将申请真实证书)"
echo "2) 测试环境 (dry-run，用于测试配置，不会消耗申请次数)"
read -p "请输入您的选择 (1 或 2): " CHOICE

CERTBOT_CMD=""
case $CHOICE in
    1)
        echo "您选择了正式环境。"
        CERTBOT_CMD="sudo certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --no-eff-email"
        ;;
    2)
        echo "您选择了测试环境。"
        CERTBOT_CMD="sudo certbot certonly --nginx --dry-run -d "$DOMAIN" --email "$EMAIL" --agree-tos --no-eff-email"
        ;;
    *)
        echo "无效的选择，退出脚本。"
        exit 1
        ;;
esac

# === 安装 Certbot（如果未安装） ===
if ! command -v certbot &> /dev/null; then
    echo "检测到 Certbot 未安装，正在安装..."
    sudo apt update
    sudo apt install certbot python3-certbot-nginx -y
fi

# === 申请并自动配置证书 ===
echo "正在为 $DOMAIN 申请 SSL 证书..."

# 使用 eval 来执行动态构建的命令
eval $CERTBOT_CMD

if [ $? -eq 0 ]; then
    echo "==========================================================="
    if [ "$CHOICE" == "1" ]; then
        echo "恭喜！HTTPS 已成功配置在 https://$DOMAIN"
        echo "证书已部署，Nginx 已重载。"
    else
        echo "证书测试申请成功！您的配置没有问题。"
        echo "如果您希望申请真实证书，请再次运行此脚本并选择正式环境。"
    fi
    echo "==========================================================="
else
    echo "证书申请或配置失败，请检查 /var/log/letsencrypt/letsencrypt.log 获取更多信息。"
fi