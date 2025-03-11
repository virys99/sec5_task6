#!/bin/bash


declare -A osInfo;
osInfo[/etc/redhat-release]=yum
osInfo[/etc/arch-release]=pacman
osInfo[/etc/gentoo-release]=emerge
osInfo[/etc/SuSE-release]=zypp
osInfo[/etc/debian_version]=apt
osInfo[/etc/alpine-release]=apk

for f in ${!osInfo[@]}
do
    if [[ -f $f ]];then
        echo Package manager: ${osInfo[$f]}
	package_manager=${osInfo[$f]}
    fi
done

IPADDR=$(ip a | grep -P 'inet\s.+ens\d+$' | awk '{print $2}' | head -1 -c -4)

#For debian based distro
if [ $package_manager == "apt" ]; then
apt update -y
apt install nginx phpmyadmin mariadb-server php-fpm composer openssl nftables -y

#Ngin config
tee /etc/nginx/sites-enabled/default <<EOF
server {
        listen 80;
        listen [::]:80;
        root /var/www/html/bagisto/public;
        index index.php;

        location /phpmyadmin {
                root /usr/share/;
                index index.php index.html index.htm;
        }
        location ~ ^/phpmyadmin/(.+\.php)$ {
                try_files \$uri =404;
                root /usr/share/;
                fastcgi_pass unix:/run/php/php8.1-fpm.sock;
                fastcgi_index index.php;
                fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
                include /etc/nginx/fastcgi_params;
                }

        location ~* ^/phpmyadmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))$ {
                root /usr/share/;
                }

        location / {
                root        /var/www/html/bagisto/public;
                try_files   \$uri /index.php\$is_args\$args;
                index index.php;
                }

        location  ~ \.php$ {
                fastcgi_pass    unix:/run/php/php8.1-fpm.sock;
                fastcgi_param SCRIPT_FILENAME \$request_filename;
                include fastcgi_params;
                fastcgi_intercept_errors on;
                }
}
EOF

#Bagisto install

#Create directory
mkdir -p /var/www/html/bagisto
cd /var/www/html
#Install bagisto via composer
composer create-project bagisto/bagisto

cp /var/www/html/bagisto/.env.example /var/www/html/bagisto/.env
sed -i 's/DB_USERNAME=.*/DB_USERNAME=bagisto/g' /var/www/html/bagisto/.env
sed -i 's/DB_DATABASE=.*/DB_DATABASE=bagisto/g' /var/www/html/bagisto/.env

# replace "-" with "_" for database username
MAINDB=(phpmyadmin bagisto)

# If /root/.my.cnf exists then it won't ask for root password
if [ -f /root/.my.cnf ]; then

    for element in "${MAINDB[@]}"; do
        PASSWDDB="$(openssl rand -base64 12)"
        mysql  <<EOF
        CREATE DATABASE IF NOT EXISTS ${element} /*\!40100 DEFAULT CHARACTER SET utf8 */;
        DROP USER IF EXISTS '${element}'@'localhost';
        CREATE USER '${element}'@'localhost' IDENTIFIED BY '${PASSWDDB}';
        GRANT ALL PRIVILEGES ON ${element}.* TO '${element}'@'localhost';
        FLUSH PRIVILEGES;
EOF

        if [ "$element" == "bagisto" ]; then
        sed -i 's/DB_PASSWORD=.*/DB_PASSWORD='"${PASSWDDB}"'/g' /var/www/html/bagisto/.env
        fi
        if [ "$element" == "phpmyadmin" ]; then
        sed -i 's/$dbpass=.*/$dbpass='"'${PASSWDDB}'"';/g' /etc/phpmyadmin/config-db.php
        fi
    done

# If /root/.my.cnf doesn't exist then it'll ask for root password
else
    echo "Please enter root user MySQL password!"
    echo "Note: password will be hidden when typing"
    read -sp rootpasswd
    for element in "${MAINDB[@]}"; do
        PASSWDDB="$(openssl rand -base64 12)"
        
        mysql -uroot -p${rootpasswd} <<EOF
        CREATE DATABASE IF NOT EXISTS ${element} /*\!40100 DEFAULT CHARACTER SET utf8 */;
	    DROP USER IF EXISTS '${element}'@'localhost';
        CREATE USER '${element}'@'localhost' IDENTIFIED BY '${PASSWDDB}';
        GRANT ALL PRIVILEGES ON ${element}.* TO '${element}'@'localhost';
        FLUSH PRIVILEGES;
EOF

        if [ "$element" == "bagisto" ]; then
        sed -i 's/DB_PASSWORD=.*/DB_PASSWORD='"${PASSWDDB}"'/g' /var/www/html/bagisto/.env
        fi
        if [ "$element" == "phpmyadmin" ]; then
        sed -i 's/$dbpass=.*/$dbpass='"'${PASSWDDB}'"';/g' /etc/phpmyadmin/config-db.php
        fi
    done
fi


#Finishing installation bagisto
cd /var/www/html/bagisto
php artisan bagisto:install

# Change owner to www-data
chown -R www-data:www-data /var/www/html/bagisto

#Service restart
service php8.1-fpm restart
service nginx restart

# Disable firewalld
systemctl disable --now ufw

# nftables setup

tee /etc/nftables.conf <<EOF

flush ruleset

table inet filter {
        chain input {
                type filter hook input priority filter; policy drop;
                # Allow loopback
                iifname "lo" accept
                # Allow icmp
                icmp type echo-request limit rate 10/second accept
                # Allow esteblished,related
                ct state related,established counter accept
                # Allow ssh from all ports
                tcp dport 22 accept
                # Allow 80 port for WEB
                tcp dport 80 accept
        }
        chain forward {
                type filter hook forward priority filter;
        }
        chain output {
                type filter hook output priority filter;
        }
}

EOF

# Enable and start nftables
systemctl enable --now nftables



#For RHEL based distro
elif [ $package_manager == "yum" ]; then
yum install epel-release -y
yum install http://rpms.remirepo.net/enterprise/remi-release-9.rpm -y
yum install dnf-utils -y
yum module reset php -y
yum module install php:remi-8.1 -y
yum install nginx phpmyadmin mariadb-server php-fpm composer openssl unzip nftables -y

#Nginx config
tee /etc/nginx/conf.d/default.conf <<EOF
server {
        listen 80;
        listen [::]:80;
        root /var/www/html/bagisto/public;
        index index.php;

        location /phpMyAdmin {
                root /usr/share/;
                index index.php index.html index.htm;
        }
        location ~ ^/phpMyAdmin/(.+\.php)$ {
                try_files \$uri =404;
                root /usr/share/;
                fastcgi_pass unix:/run/php-fpm/www.sock;
                fastcgi_index index.php;
                fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
                include /etc/nginx/fastcgi_params;
                }

        location ~* ^/phpMyAdmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))$ {
                root /usr/share/;
                }

        location / {
                root        /var/www/html/bagisto/public;
                try_files   \$uri /index.php\$is_args\$args;
                index index.php;
                }

        location  ~ \.php$ {
                fastcgi_pass    unix:/run/php-fpm/www.sock;
                fastcgi_param SCRIPT_FILENAME \$request_filename;
                include fastcgi_params;
                fastcgi_intercept_errors on;
                }
}
EOF

#Bagisto install

#Create directory
mkdir -p /var/www/html/bagisto
cd /var/www/html

# Change owner session.save.path in php-fpm
chown -R root:nginx /var/lib/php/
# Change user and group for php-fpm process
sed -i 's/^user =.*/user = nginx/g' /etc/php-fpm.d/www.conf
sed -i 's/^group =.*/group = nginx/g' /etc/php-fpm.d/www.conf
# Enable and start services
systemctl enable --now nginx
systemctl enable --now php-fpm
systemctl enable --now mariadb
#Install bagisto via composer
composer create-project bagisto/bagisto

cp /var/www/html/bagisto/.env.example /var/www/html/bagisto/.env
sed -i 's/DB_USERNAME=.*/DB_USERNAME=bagisto/g' /var/www/html/bagisto/.env
sed -i 's/DB_DATABASE=.*/DB_DATABASE=bagisto/g' /var/www/html/bagisto/.env

# replace "-" with "_" for database username
MAINDB=(phpmyadmin bagisto)

# If /root/.my.cnf exists then it won't ask for root password
if [ -f /root/.my.cnf ]; then

    for element in "${MAINDB[@]}"; do
        PASSWDDB="$(openssl rand -base64 12)"
        mysql  <<EOF
        CREATE DATABASE IF NOT EXISTS ${element} /*\!40100 DEFAULT CHARACTER SET utf8 */;
        DROP USER IF EXISTS '${element}'@'localhost';
        CREATE USER '${element}'@'localhost' IDENTIFIED BY '${PASSWDDB}';
        GRANT ALL PRIVILEGES ON ${element}.* TO '${element}'@'localhost';
        FLUSH PRIVILEGES;
EOF

        if [ "$element" == "bagisto" ]; then
        sed -i 's/DB_PASSWORD=.*/DB_PASSWORD='"${PASSWDDB}"'/g' /var/www/html/bagisto/.env
        fi
        #if [ "$element" == "phpmyadmin" ]; then
        #sed -i 's/$dbpass=.*/$dbpass='"'${PASSWDDB}'"';/g' /etc/phpmyadmin/config-db.php
        #fi
    done

# If /root/.my.cnf doesn't exist then it'll ask for root password
else
    echo "Please enter root user MySQL password!"
    echo "Note: password will be hidden when typing"
    read -sp rootpasswd
    for element in "${MAINDB[@]}"; do
        PASSWDDB="$(openssl rand -base64 12)"
        
        mysql -uroot -p${rootpasswd} <<EOF
        CREATE DATABASE IF NOT EXISTS ${element} /*\!40100 DEFAULT CHARACTER SET utf8 */;
	    DROP USER IF EXISTS '${element}'@'localhost';
        CREATE USER '${element}'@'localhost' IDENTIFIED BY '${PASSWDDB}';
        GRANT ALL PRIVILEGES ON ${element}.* TO '${element}'@'localhost';
        FLUSH PRIVILEGES;
EOF

        if [ "$element" == "bagisto" ]; then
        sed -i 's/DB_PASSWORD=.*/DB_PASSWORD='"${PASSWDDB}"'/g' /var/www/html/bagisto/.env
        fi
        #if [ "$element" == "phpmyadmin" ]; then
        #sed -i 's/$dbpass=.*/$dbpass='"'${PASSWDDB}'"';/g' /etc/phpmyadmin/config-db.php
        #fi
    done
fi



#Finishing installation bagisto
cd /var/www/html/bagisto
php artisan bagisto:install

# Change owner to www-data
chown -R nginx:nginx /var/www/html/bagisto

#Fix Selinux permissions
setsebool -P httpd_unified 1
setsebool -P httpd_can_network_connect_db 1

#Service restart
service php-fpm restart
service nginx restart

# Disable firewalld
systemctl disable --now firewalld

# nftables setup

tee /etc/sysconfig/nftables.conf <<EOF

flush ruleset

table inet filter {
        chain input {
                type filter hook input priority filter; policy drop;
                # Allow loopback
                iifname "lo" accept
                # Allow icmp
                icmp type echo-request limit rate 10/second accept
                # Allow esteblished,related
                ct state related,established counter accept
                # Allow ssh from all ports
                tcp dport 22 accept
                # Allow 80 port for WEB
                tcp dport 80 accept
        }
        chain forward {
                type filter hook forward priority filter;
        }
        chain output {
                type filter hook output priority filter;
        }
}

EOF

# Enable and start nftables
systemctl enable --now nftables

fi
