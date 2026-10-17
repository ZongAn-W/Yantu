#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

trap 'printf "Setup stopped at line %s. Send the error above; do not send .env contents.\n" "$LINENO" >&2' ERR

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

server_ip=${1:-47.116.63.161}
project_dir=/opt/sjtu-study-planner
api_dir=$project_dir/apps/api
certbot=/opt/study-planner-certbot/bin/certbot
nginx_config=/etc/nginx/conf.d/study-planner-ip.conf
cert_name=study-planner-ip
webroot=/var/lib/study-planner-acme

python3 - "$server_ip" <<'PY'
import ipaddress
import sys
ipaddress.IPv4Address(sys.argv[1])
PY

for executable in nginx docker systemctl curl python3 runuser; do
  command -v "$executable" >/dev/null
done
test -x "$certbot"
test -f "$project_dir/apps/flutter_client/build/web/index.html"
test -f "$api_dir/.env"
runuser -u www-data -- test -r "$project_dir/apps/flutter_client/build/web/index.html"
nginx -t
curl --fail --silent --show-error --max-time 10 http://127.0.0.1:8787/api/health >/dev/null

temporary_dir=$(mktemp -d /tmp/study-planner-web.XXXXXXXX)
http_config=$temporary_dir/http.conf
https_config=$temporary_dir/https.conf

cat > "$http_config" <<EOF
# Managed by apps/api/setup-ip-web.sh
server {
    listen 80;
    server_name $server_ip;
    root $project_dir/apps/flutter_client/build/web;
    index index.html;

    location ^~ /.well-known/acme-challenge/ {
        root $webroot;
        default_type text/plain;
        try_files \$uri =404;
    }
    location ^~ /api/ {
        return 403;
    }
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF

cat > "$https_config" <<EOF
# Managed by apps/api/setup-ip-web.sh
server {
    listen 80;
    server_name $server_ip;

    location ^~ /.well-known/acme-challenge/ {
        root $webroot;
        default_type text/plain;
        try_files \$uri =404;
    }
    location / {
        return 301 https://$server_ip\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name $server_ip;
    ssl_certificate /etc/letsencrypt/live/$cert_name/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$cert_name/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    server_tokens off;
    root $project_dir/apps/flutter_client/build/web;
    index index.html;

    location ^~ /api/ {
        proxy_pass http://127.0.0.1:8787;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 10s;
        proxy_read_timeout 300s;
    }
    location ^~ /assets/ {
        try_files \$uri =404;
        add_header Cache-Control "no-cache";
    }
    location = /index.html {
        add_header Cache-Control "no-cache";
    }
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF

if [[ -e "$nginx_config" ]] && ! cmp -s "$nginx_config" "$http_config" && ! cmp -s "$nginx_config" "$https_config"; then
  echo "An existing, different Nginx configuration was found. No configuration was replaced." >&2
  exit 1
fi

install -d -m 755 "$webroot/.well-known/acme-challenge"
if [[ ! -e "$nginx_config" ]] || ! cmp -s "$nginx_config" "$https_config"; then
  install -m 644 "$http_config" "$nginx_config"
fi
nginx -t
systemctl enable --now nginx
systemctl reload nginx

printf 'study-planner-acme-ready\n' > "$webroot/.well-known/acme-challenge/study-planner-probe"
chmod 644 "$webroot/.well-known/acme-challenge/study-planner-probe"
curl --fail --silent --show-error --max-time 10 \
  -H "Host: $server_ip" http://127.0.0.1/.well-known/acme-challenge/study-planner-probe
echo "Requesting a trusted IP certificate. Certbot may ask for an email and agreement to its terms."
"$certbot" certonly --webroot --webroot-path "$webroot" \
  --ip-address "$server_ip" --preferred-profile shortlived \
  --cert-name "$cert_name" --keep-until-expiring \
  --deploy-hook 'nginx -t && systemctl reload nginx'

python3 - "$api_dir/.env" "$server_ip" <<'PY'
import os
from pathlib import Path
import re
import sys
import tempfile
import time

path = Path(sys.argv[1])
original = path.read_bytes()
text = original.decode('utf-8')
pattern = r'^WEB_ORIGIN=[^\r\n]*'
if len(re.findall(pattern, text, re.MULTILINE)) != 1:
    raise SystemExit('Expected exactly one WEB_ORIGIN entry. The .env file was not changed.')
updated = re.sub(pattern, 'WEB_ORIGIN=https://' + sys.argv[2], text, flags=re.MULTILINE).encode('utf-8')
if updated != original:
    backup = path.with_name('.env.before-ip-web-' + str(time.time_ns()))
    descriptor = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'wb') as stream:
        stream.write(original)
    descriptor, temporary = tempfile.mkstemp(prefix='.env.web-', dir=path.parent)
    with os.fdopen(descriptor, 'wb') as stream:
        stream.write(updated)
    os.replace(temporary, path)
    print('WEB_ORIGIN updated; original .env was backed up with mode 600.')
else:
    print('WEB_ORIGIN already matches the HTTPS address.')
PY

docker compose --env-file "$api_dir/.env" -f "$api_dir/docker-compose.server.yml" \
  up -d --no-deps --force-recreate --wait --wait-timeout 120 api
install -m 644 "$https_config" "$nginx_config"
nginx -t
systemctl reload nginx

service_path=/etc/systemd/system/study-planner-certbot-renew.service
timer_path=/etc/systemd/system/study-planner-certbot-renew.timer
cat > "$temporary_dir/renew.service" <<EOF
[Unit]
Description=Renew the study planner IP certificate
Wants=network-online.target
After=network-online.target nginx.service

[Service]
Type=oneshot
ExecStart=$certbot renew --quiet --cert-name $cert_name
EOF
cat > "$temporary_dir/renew.timer" <<'EOF'
[Unit]
Description=Check the study planner IP certificate every eight hours

[Timer]
OnCalendar=*-*-* 00,08,16:00:00
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOF
for kind in service timer; do
  target="/etc/systemd/system/study-planner-certbot-renew.$kind"
  if [[ -e "$target" ]] && ! cmp -s "$target" "$temporary_dir/renew.$kind"; then
    echo "An existing, different renewal unit was found; it was not overwritten." >&2
    exit 1
  fi
done
install -m 644 "$temporary_dir/renew.service" "$service_path"
install -m 644 "$temporary_dir/renew.timer" "$timer_path"
systemctl daemon-reload
systemctl enable --now study-planner-certbot-renew.timer

curl --fail --silent --show-error --max-time 15 \
  --resolve "$server_ip:443:127.0.0.1" "https://$server_ip/api/health"
printf '\nWebsite ready: https://%s/\n' "$server_ip"
echo "Certificate renewal timer enabled."
