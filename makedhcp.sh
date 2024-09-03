#!/bin/bash

# Function to check if the xCAT service is running
wait_for_xcat() {
    while true; do
        if ps aux | grep -q "[x]catd: SSL listener"; then
            echo "xCAT service is running."
            break
        else
            echo "Waiting for xCAT service to start..."
            sleep 300
        fi
    done
}

# Check if /etc/dhcp/dhcpd.conf exists
if [ -f /etc/dhcp/dhcpd.conf ]; then
    # Wait for the xCAT service to start
    wait_for_xcat

    # Run the makedhcp command after waiting for the xCAT service
    makehosts
    makedhcp -n
    nohup /usr/sbin/dhcpd -f -cf /etc/dhcp/dhcpd.conf -user dhcpd -group dhcpd --no-pid &
    makedhcp -a
else
    echo "/etc/dhcp/dhcpd.conf file not present"
fi
