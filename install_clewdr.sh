sudo mkdir -p /etc/clewdr
cd /etc/clewdr || exit

echo "=== Clewdr 一键部署 ==="

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

echo "=== Clewdr 部署完成 ==="
sudo docker ps | grep clewdr
echo "可用日志查看： sudo docker logs -f clewdr"
