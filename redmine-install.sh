# !/bin/bash
  
# Script for setting up Redmine 4.0.2 on Ubuntu 18.04.
# Following this blog post: https://www.rosehosting.com/blog/how-to-install-redmine-on-ubuntu-18-04/
# author Anton Strand
# 2019-10-18

# Generate password for database
PASSWORD=$(cat /dev/urandom | LC_CTYPE=C tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
ROOT_PASSWORD=$(cat /dev/urandom | LC_CTYPE=C tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
IP=$(dig +short myip.opendns.com @resolver1.opendns.com)
DOMAIN_NAME=$(sed 's/.\{1\}$//' <<< $(dig +short -x $IP))

# Check if email is provided
if [[ -z $1 ]]; then
  echo "You need to provide an email address for creating SSL cert"
  exit 1;
  
  # Validate provided email
  isValidEmail="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$" 
  if [[ ! $1 =~ $isValidEmail ]]; then 
    echo "The email is invalid";
    exit 1;
  fi
fi

EMAIL=$1

echo "--------------------------------------"
echo "  Setting up Redmine"
echo "--------------------------------------"
echo "  IP:           $IP"
echo "  Domain name:  $DOMAIN_NAME"
echo "  Email:        $EMAIL"
echo "--------------------------------------"

echo ##################################
echo Step 1: Update
echo ##################################
sudo apt-get -y update
sudo DEBIAN_FRONTEND=noninteractive apt-get -yq upgrade

echo ##################################
echo Step 2: Install MySQL
echo ##################################
sudo apt-get -y install mysql-server

echo Enable auto restart after reboot
sudo systemctl enable mysql -y

echo Increase security
sudo mysql -u root << EOF
UPDATE mysql.user SET Password=PASSWORD('$ROOT_PASSWORD') WHERE User='root';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.db WHERE Db='test' OR Db='test_%';
FLUSH PRIVILEGES;
EOF

echo ##################################
echo Step 3: Create DB for Redmine
echo ##################################
sudo mysql -uroot -p${ROOT_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS redmine_db;GRANT ALL PRIVILEGES ON redmine_db.* TO 'redmine_user'@'localhost' IDENTIFIED BY '$PASSWORD';FLUSH PRIVILEGES;"

echo ##################################
echo Step 4: Install Ruby
echo ##################################
sudo apt-get -y install ruby-full

echo ##################################
echo Step 5: Install Nginx and Passenger
echo ##################################
sudo apt-get -y install nginx
sudo systemctl start nginx
sudo systemctl enable nginx
sudo apt-get -y install dirmngr gnupg apt-transport-https ca-certificates
sudo apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 561F9B9CAC40B2F7
sudo add-apt-repository 'deb https://oss-binaries.phusionpassenger.com/apt/passenger bionic main'
sudo apt-get -y update
sudo apt-get -y install libnginx-mod-http-passenger

echo ##################################
echo Step 6: Download and Install Redmine
echo ##################################
sudo apt-get -y install build-essential libmysqlclient-dev imagemagick libmagickwand-dev
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
sudo apt-get -y update
sudo apt-get -y install software-properties-common
sudo add-apt-repository universe -y
sudo add-apt-repository ppa:certbot/certbot -y
sudo apt-get -y update

echo  2. Install Certbot
sudo apt-get -y install certbot python-certbot-nginx

echo  3. Setup NGNIX
sudo certbot --non-interactive --agree-tos -d $DOMAIN_NAME -m $EMAIL --nginx

echo "# Redirect HTTP -> HTTPS
server {
    listen 80;
    server_name www.$DOMAIN_NAME $DOMAIN_NAME;

    return 301 https://$DOMAIN_NAME$request_uri;
}

# Redirect WWW -> NON WWW
server {
    listen 443 ssl http2;
    server_name www.$DOMAIN_NAME;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$DOMAIN_NAME/chain.pem;

    return 301 https://$DOMAIN_NAME$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN_NAME;

    root /opt/redmine/public;

    # SSL parameters
    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$DOMAIN_NAME/chain.pem;

    # log files
    access_log /var/log/nginx/$DOMAIN_NAME.access.log;
    error_log /var/log/nginx/$DOMAIN_NAME.error.log;

    passenger_enabled on;
    passenger_min_instances 1;
    client_max_body_size 10m;
}" | sudo tee -a /etc/nginx/sites-available/$DOMAIN_NAME.conf > /dev/null

sudo ln -s /etc/nginx/sites-available/$DOMAIN_NAME.conf /etc/nginx/sites-enabled/$DOMAIN_NAME.conf
sudo nginx -t
sudo service nginx reload

echo ##################################
echo  Finally: Clean
echo ##################################
sudo apt-get -y autoclean
sudo apt-get -y autoremove

echo "Redmine is installed and can be found at www.$DOMAIN_NAME"
