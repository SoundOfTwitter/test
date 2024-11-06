#!/bin/bash

# 变量设置
server_IP=$(wget -qO- ifconfig.me)
# read -p "请输入 server_IP: " server_IP
# read -p "请输入 strong_passwd: " strong_passwd
strong_passwd=$(< /dev/urandom tr -dc 'A-Za-z0-9' | head -c 26)

apt update && apt install -y curl gnupg2 software-properties-common lsb-release ca-certificates && curl -L https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg | apt-key add - && echo "deb https://packages.matrix.org/debian/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/matrix-org.list && apt update

# 设置 Synapse server_name 为 server_IP，避免交互式配置
echo "matrix-synapse matrix-synapse/server-name string $server_IP" | debconf-set-selections

# 设置 DEBIAN_FRONTEND 环境变量为 noninteractive，避免交互提示
export DEBIAN_FRONTEND=noninteractive

apt update && apt install -y matrix-synapse-py3

# 等待10秒后继续
sleep 10

# 创建自签名证书，避免手动输入信息
openssl req -new -x509 \
    -keyout /etc/ssl/private/matrix-selfsigned.key \
    -out /etc/ssl/certs/matrix-selfsigned.crt \
    -days 365 -nodes \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=$server_IP"

chmod 600 /etc/ssl/private/matrix-selfsigned.key && apt install -y nginx

# 配置 Nginx
cat << EOF > /etc/nginx/sites-available/matrix
server {
    listen 443 ssl;
    server_name $server_IP;

    ssl_certificate /etc/ssl/certs/matrix-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/matrix-selfsigned.key;

    location / {
        proxy_pass http://localhost:8008;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 80;
    server_name $server_IP;
    return 301 https://\$server_name\$request_uri;
}
EOF

ln -s /etc/nginx/sites-available/matrix /etc/nginx/sites-enabled/

nginx -t

sleep 10

systemctl restart nginx

sleep 20

# 配置 /etc/matrix-synapse/homeserver.yaml
# 检查是否传入了变量 server_IP 和 strong_passwo
#if [ -z "$server_IP" ] || [ -z "$strong_passwo" ]; then
    #echo "请设置 server_IP 和 strong_passwo 变量"
    #exit 1
#fi

# 定义 homeserver.yaml 文件路径
HOMESERVER_FILE="/etc/matrix-synapse/homeserver.yaml"

# 备份原始文件
#cp "$HOMESERVER_FILE" "${HOMESERVER_FILE}.bak"

# 写入新的内容
cat > "$HOMESERVER_FILE" <<EOL
# Homeserver configuration file for Synapse
# More documentation: https://matrix-org.github.io/synapse/latest/

# Server information
server_name: "$server_IP"  # 使用公网IP或本地IP（不要使用域名）
pid_file: "/var/run/matrix-synapse.pid"

# Listeners (this controls which ports Synapse listens on)
listeners:
  - port: 8008
    tls: false  # 关闭TLS，使用自签名证书
    type: http
    x_forwarded: true
    bind_addresses: ['::1', '127.0.0.1']  # 仅监听本地IP，适用于自签名证书
    resources:
      - names: [client, federation]
        compress: false

# Database configuration
database:
  name: sqlite3
  args:
    database: /var/lib/matrix-synapse/homeserver.db

# Log file location and logging configuration
log_config: "/etc/matrix-synapse/log.yaml"

# Media store path
media_store_path: /var/lib/matrix-synapse/media

# Signing key path (for signing events in the federation)
signing_key_path: "/etc/matrix-synapse/homeserver.signing.key"

# Trusted key servers
trusted_key_servers: []  # 不与其他Matrix服务器通信，禁用所有信任的服务器

# Trusted proxies (useful for reverse proxies)
trusted_proxies:
  - 127.0.0.1

# Registration and password reset settings
enable_registration: false  # 禁用公开注册
password_reset:
  enabled: true  # 启用密码重置功能
  shared_secret: "$strong_passwd"  # 可选，设置共享密钥保护密码重置功能

# Email configuration for password reset emails
email:
  smtp_host: "smtp.163.com"  # 邮件服务器的地址（例如：smtp.gmail.com）
  smtp_port: 465                   # SMTP服务器端口（587 为常见的安全端口）
  smtp_user: "liuxiantao328@163.com"  # 用于登录SMTP服务器的邮箱用户名
  smtp_pass: "VNBGPCYDIJNEUBAS"    # 邮件服务器密码
  require_transport_security: true    # 是否要求使用TLS
  notif_from: "Your Matrix Server <no-reply@163.com>"  # 发件人地址

# Public base URL (This will be used in the links for password resets)
public_baseurl: "https://$server_IP:8008"  # 你的服务器地址（公网IP）

# Federation settings (disable federation)
federation:
  enable: false  # 禁用联邦，不与其他Matrix服务器通信

# Media settings
media:
  store_path: "/var/lib/matrix-synapse/media"
  enable_media_repo: false  # 禁用媒体存储库，适用于不希望使用大量媒体存储的场景

# Other configuration settings

EOL

# 输出成功信息
echo "已成功更新 homeserver.yaml 文件。"

systemctl restart matrix-synapse
