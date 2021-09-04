FROM nginx:stable
RUN  apt-get update \
      && apt-get install -y cron certbot python-certbot-nginx bash wget \
      && rm -rf /var/lib/apt/lists/* \
      && echo "PATH=$PATH" > /etc/cron.d/certbot-renew  \
      && echo "@monthly certbot renew --nginx >> /var/log/cron.log 2>&1" >>/etc/cron.d/certbot-renew \
      && crontab /etc/cron.d/certbot-renew
COPY ./docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
VOLUME /etc/letsencrypt




