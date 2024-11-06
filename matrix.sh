#!/bin/bash

# 变量设置
server_IP=$(wget -qO- ifconfig.me)
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
# Configuration file for Synapse. 
#
# This is a YAML file: see [1] for a quick introduction. Note in particular
# that *indentation is important*: all the elements of a list or dictionary
# should have the same indentation.
#
# [1] https://docs.ansible.com/ansible/latest/reference_appendices/YAMLSyntax.html
#
# For more information on how to configure Synapse, including a complete accounting of
# each option, go to docs/usage/configuration/config_documentation.md or
# https://matrix-org.github.io/synapse/latest/usage/configuration/config_documentation.html
#
# This is set in /etc/matrix-synapse/conf.d/server_name.yaml for Debian installations.
server_name: "$server_IP"
pid_file: "/var/run/matrix-synapse.pid"
listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    bind_addresses: ['::1', '127.0.0.1']
    resources:
      - names: [client, federation]
        compress: false
database:
  name: sqlite3
  args:
    database: /var/lib/matrix-synapse/homeserver.db
log_config: "/etc/matrix-synapse/log.yaml"
media_store_path: /var/lib/matrix-synapse/media
signing_key_path: "/etc/matrix-synapse/homeserver.signing.key"
trusted_key_servers:
  - server_name: "matrix.org"
trusted_proxies:
  - 127.0.0.1
enable_registration: true
enable_email_verification: true
registration_shared_secret: "$strong_passwd"

email:
  smtp_host: "smtp.163.com"
  smtp_port: 465
  smtp_user: "liuxiantao328@163.com"
  smtp_pass: "VNBGPCYDIJNEUBAS"
  require_transport_security: true
  notif_from: "Your App Name <liuxiantao328@163.com>"
  
enable_password_reset: true

public_baseurl: "https://$server_IP/"
EOL

# 输出成功信息
echo "已成功更新 homeserver.yaml 文件。"

systemctl restart matrix-synapse
