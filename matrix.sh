#!/bin/bash

# 变量设置
read -p "请输入 server_IP: " server_IP
read -p "请输入 strong_passwd: " strong_passwd

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

sed -i "14c server_name: \"$server_IP\"" /etc/matrix-synapse/homeserver.yaml

echo 'trusted_proxies:' | tee -a /etc/matrix-synapse/homeserver.yaml

echo '  - 127.0.0.1' | tee -a /etc/matrix-synapse/homeserver.yaml

echo 'enable_registration: true' | tee -a /etc/matrix-synapse/homeserver.yaml

echo "registration_shared_secret: \"$strong_passwd\"" | tee -a /etc/matrix-synapse/homeserver.yaml

systemctl restart matrix-synapse
