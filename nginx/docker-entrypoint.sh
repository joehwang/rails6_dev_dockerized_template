#!/bin/sh
set -e
echo "Your domain list: $DOMAIN_LIST"
cp /tmp/default.conf /tmp/$NGINX_HOST.conf
if [ -d "/etc/letsencrypt/live/$NGINX_HOST" ]
then
    echo "Let's Encrypt SSL already setup."
    sed -i -e 's/###//g' /tmp/$NGINX_HOST.conf
    envsubst '${NGINX_HOST}' < /tmp/$NGINX_HOST.conf > /etc/nginx/conf.d/default.conf 
    nginx -g 'daemon off;'
else
    echo "Applying for a SSL Certificate from Let's Encrypt"
    certbot certonly --standalone $CERTBOT_TEST_MODE --email $CERTBOT_EMAIL --agree-tos --preferred-challenges http -n -d $DOMAIN_LIST
    echo "Restart NGINX container !"
fi

exec "$@"
