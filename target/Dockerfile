# Default: PHP 8.4.4 (0x4148 reference lab). For VTBW profile use: PHP_TARGET_VERSION=8.1.34
ARG PHP_TARGET_VERSION=8.4.4
FROM php:${PHP_TARGET_VERSION}-fpm-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx curl \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/log/php-fpm /var/lib/php/sessions /run/php \
    && chown www-data:www-data /var/lib/php/sessions

COPY conf/php.ini /usr/local/etc/php/php.ini
COPY conf/www.conf /usr/local/etc/php-fpm.d/www.conf
COPY conf/php-fpm.conf /usr/local/etc/php-fpm.conf
COPY conf/nginx.conf /etc/nginx/nginx.conf
COPY webroot/ /var/www/html/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80
CMD ["/entrypoint.sh"]
