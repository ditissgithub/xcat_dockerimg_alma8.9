#!/bin/bash

# Assign environment variables to local variables
mysql_port=${MYSQL_PORT}
mysqladmin_pw=${MYSQLADMIN_PW}
mysqlroot_pw=${MYSQLROOT_PW}

# Define MySQL root credentials
MYSQL_ROOT_USER="root"

# Maximum retries and delay between retries
MAX_RETRIES=10
RETRY_DELAY=10  # 10 seconds delay

# Function to check for required directories and osimage
check_xcat_data() {
    [ -d /xcatdata/etc ] && [ -d /xcatdata/install ] && [ -d /xcatdata/tftpboot ] && [ -d /xcatdata/opt ] && \
    [ -d /xcatdata/install/netboot ] && lsdef -t osimage | grep -q 'netboot'
}

# Check if /var/lib/mysql/xcatdb exists
if [ -f /var/lib/mysql/xcatdb/db.opt ] && [ -f /etc/xcat/cfgloc ]; then
    # Start the MySQL service
    nohup /usr/bin/mysqld_safe --user=mysql --basedir=/usr --datadir=/var/lib/mysql --socket=/var/lib/mysql/mysql.sock --port=$mysql_port > /dev/null 2>&1 &
    sleep 5  # Allow time for MySQL to start

else
    # Retry loop to wait for xCAT data directories and netboot osimage to be ready
    retry_count=0
    while ! check_xcat_data && [ $retry_count -lt $MAX_RETRIES ]; do
        echo "Waiting for required directories and netboot osimage... (attempt $((retry_count+1))/$MAX_RETRIES)"
        retry_count=$((retry_count+1))
        sleep $RETRY_DELAY
    done

    # After retrying, check if the condition is met
    if check_xcat_data; then
        # Create xcatdb for MySQL
        echo "Setting up MySQL database for xCAT..."
        mysqlsetup -i -p $mysql_port --XCATMYSQLADMIN_PW $mysqladmin_pw --XCATMYSQLROOT_PW $mysqlroot_pw > /dev/null 2>&1 &
        sleep 180 # Allow time for xcatdb to be updated from SQLite
    else
        echo "Required directories or netboot osimage not found after retries, exiting..."
        exit 1
    fi
fi
