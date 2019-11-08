# install-redmine
Script for installing Redmine 4.0.2 on Ubuntu 18.04

## How to use
These steps assume that you have downloaded the script and is currently in the same folder as the script.
1. Upload script to your server `scp redmine-install.sh [USER]@[IP]:redmine-install.sh`.
2. Login to your server shell.
3. Allow the script `chmod 777 redmine-install.sh`.
4. Run the script with an email for certbot `./redmine-install.sh email@example.com`.

## How to use without first download the script locally
These steps assume that you have [wget](https://www.gnu.org/software/wget/) installed on your server.
1. Login to your server shell.
2. Run `wget https://raw.githubusercontent.com/AntonStrand/install-redmine/master/redmine-install.sh`.
3. Allow the script `chmod 777 redmine-install.sh`.
4. Run the script with an email for certbot `./redmine-install.sh email@example.com`.
