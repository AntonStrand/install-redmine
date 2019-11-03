#!/bin/bash
  
# Script for setting up Redmine 4.0.2 on Ubuntu 18.04.
# Following this blog post: https://www.rosehosting.com/blog/how-to-install-redmine-on-ubuntu-18-04/
# author Anton Strand
# 2019-10-18

# Generate password for database
PASSWORD=$(cat /dev/urandom | LC_CTYPE=C tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

echo ##################################
echo Step 1: Update
echo ##################################
sudo apt-get update
sudo apt-get upgrade

echo ##################################
echo Step 2: Install MySQL
echo ##################################
sudo apt-get install mysql-server

echo Enable auto restart after reboot
sudo systemctl enable mysql

echo Increase security
echo "Next up is to set up important security tasks like a root password, disable remote root login, remove anonymous users, etc. If the script asks for the root password, just press the [Enter] key, as no root password is set by default."
sudo mysql_secure_installation

echo ##################################
echo Step 3: Create DB for Redmine
echo ##################################
echo "Use the password you used during the security section."
echo "Note: password will be hidden when typing"
read -s passwd
sudo mysql -uroot -p${passwd} -e "CREATE DATABASE IF NOT EXISTS redmine_db;GRANT ALL PRIVILEGES ON redmine_db.* TO 'redmine_user'@'localhost' IDENTIFIED BY '$PASSWORD';FLUSH PRIVILEGES;"

echo ##################################
echo Step 4: Install Ruby
echo ##################################
sudo apt-get install ruby-full

echo ##################################
echo Step 5: Install Nginx and Passenger
echo ##################################
sudo apt-get install nginx
sudo systemctl start nginx
sudo systemctl enable nginx
sudo apt-get install dirmngr gnupg apt-transport-https ca-certificates
sudo apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 561F9B9CAC40B2F7
sudo add-apt-repository 'deb https://oss-binaries.phusionpassenger.com/apt/passenger bionic main'
sudo apt-get update
sudo apt-get install libnginx-mod-http-passenger

echo ##################################
echo Step 6: Download and Install Redmine
echo ##################################
sudo apt-get install build-essential libmysqlclient-dev imagemagick libmagickwand-dev
sudo wget https://www.redmine.org/releases/redmine-4.0.2.zip -O /opt/redmine.zip
cd /opt
sudo unzip redmine.zip
sudo mv redmine-4.0.2 redmine
cd
sudo chown -R www-data:www-data /opt/redmine/
sudo chmod -R 755 /opt/redmine/

echo Configure db settings
cd /opt/redmine/config/
sudo cp configuration.yml.example configuration.yml
sudo cp database.yml.example database.yml
sudo sed -i -e 's/database: redmine/database: redmine_db/' database.yml
sudo sed -i -e 's/password: ""/password: "'"$PASSWORD"'"/' database.yml
sudo sed -i -e 's/root/redmine_user/' database.yml

echo ##################################
echo  Step 7: Install Ruby dependencie, Generate Keys, and Migrate the Database
echo ##################################
cd /opt/redmine/
sudo mkdir -p app/assets/config
sudo touch app/assets/config/manifest.js
sudo gem install bundler --no-rdoc --no-ri
sudo bundle install --without development test postgresql sqlite
sudo bundle exec rake generate_secret_token
sudo RAILS_ENV=production bundle exec rake db:migrate

echo ##################################
echo  Step 8: Let\'s encrypt
echo ##################################
echo  1. Add Certbot PPA
sudo apt-get update
sudo apt-get install software-properties-common
sudo add-apt-repository universe
sudo add-apt-repository ppa:certbot/certbot
sudo apt-get update

echo  2. Install Certbot
sudo apt-get install certbot python-certbot-nginx

echo  3. Setup NGNIX
sudo certbot --nginx

read -p "Please enter your domain name: " domainName

echo "# Redirect HTTP -> HTTPS
server {
    listen 80;
    server_name www.$domainName $domainName;

    return 301 https://$domainName$request_uri;
}

# Redirect WWW -> NON WWW
server {
    listen 443 ssl http2;
    server_name www.$domainName;

    ssl_certificate /etc/letsencrypt/live/$domainName/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domainName/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$domainName/chain.pem;

    return 301 https://$domainName$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $domainName;

    root /opt/redmine/public;

    # SSL parameters
    ssl_certificate /etc/letsencrypt/live/$domainName/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domainName/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$domainName/chain.pem;

    # log files
    access_log /var/log/nginx/$domainName.access.log;
    error_log /var/log/nginx/$domainName.error.log;

    passenger_enabled on;
    passenger_min_instances 1;
    client_max_body_size 10m;
}" | sudo tee -a /etc/nginx/sites-available/$domainName.conf > /dev/null

sudo ln -s /etc/nginx/sites-available/$domainName.conf /etc/nginx/sites-enabled/$domainName.conf
sudo nginx -t
sudo service nginx reload

echo ##################################
echo  Finally: Clean
echo ##################################
sudo apt-get autoremove

echo "Redmine is installed and can be found at www.$domainName"
