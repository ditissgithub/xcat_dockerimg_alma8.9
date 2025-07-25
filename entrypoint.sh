#!/bin/bash

# Check if xCAT and MySQL directories exist, and start services if so
if [ -f /var/lib/mysql/xcatdb/db.opt ] && [ -f /etc/xcat/cfgloc ]; then
    #echo "Starting all xCAT-related services..."
    cp -r /xcatdata/.xcat /root/.xcat
    # Start supervisord to manage xCAT services
    /usr/bin/supervisord -c /etc/supervisord.conf

else
    # Determine the OS type for logging ownership (Ubuntu vs others)
    is_ubuntu=$(test -f /etc/debian_version && echo Y)
    [[ -z ${is_ubuntu} ]] && logadm="root:" || logadm="syslog:adm"

    # Fix ownership of log files
    chown -R ${logadm} /var/log/xcat/

    # Source xCAT environment variables
    . /etc/profile.d/xcat.sh

    # Check if /xcatdata.NEEDINIT exists to initialize xCAT
    if [[ -d "/xcatdata.NEEDINIT" ]]; then
        #echo "Initializing xCAT..."

        # Sync necessary data from /xcatdata.NEEDINIT to /xcatdata
        rsync -a /xcatdata.NEEDINIT/ /xcatdata

        # Rename the initialization directory to indicate it's been processed
        mv /xcatdata.NEEDINIT /xcatdata.orig

        # Configure xCAT
        xcatconfig -d
        xcatconfig -i   # Initialize xCAT networks

        export XCATBYPASS=1

        # Set DOMAIN and DHCPINTERFACE in the site table if they do not exist
        tabdump site | grep domain || chtab key=domain site.value="${DOMAIN}"
        tabdump site | grep dhcpinterfaces || chtab key=dhcpinterfaces site.value="${DHCPINTERFACE}"

        # Update site table with master, nameservers, and forwarders values
        chtab key=master site.value="${MASTER}"
        chtab key=nameservers site.value="${NAMESERVERS}"
        chtab key=forwarders site.value="${FORWARDERS}"

        # Check if the ib0 network exists, if not, create an entry for it
        if ! tabdump networks | grep -q "ib0"; then
            chdef -t network -o ib0 net="${IB_Net}" mask="${IB_Mask}" gateway="${Xcatmaster}" \
            tftpserver="${Xcatmaster}" mgtifname=ib0 mtu=2044
        else
            echo "Entry for ib0 already exists."
        fi

        # Create or update network entries for the specified network
        if tabdump networks | grep -q "$ObjectName"; then
            chdef -t network -o "$ObjectName" dhcpserver="$Dhcpserver" gateway="$Gateway" \
            mask="$IP_Mask" mgtifname="$Mgtifname" mtu=1500 net="$IP_Net" tftpserver="$Tftpserver"
        else
            chdef -t network -o "$ObjectName" dhcpserver="$Dhcpserver" gateway="$Gateway" \
            mask="$IP_Mask" mgtifname="$Mgtifname" mtu=1500 net="$IP_Net" tftpserver="$Tftpserver"
        fi

        # Create symlink for /root/.xcat directory
        #echo "Creating symlink for /root/.xcat..."
        rsync -a /root/.xcat/* /xcatdata/.xcat
        rm -rf /root/.xcat/
        ln -sf -t /root /xcatdata/.xcat

        # Initialize loop devices for xCAT
        echo "Initializing loop devices..."
        for i in {0..7}; do
            if ! [ -b /dev/loop$i ]; then
                mknod /dev/loop$i -m0660 b 7 $i
            fi
        done

        # Workaround for missing switch_macmap
        ln -sf /opt/xcat/bin/xcatclient /opt/xcat/probe/subcmds/bin/switchprobe
    fi

    # Move the modified mysqlsetup Perl script to the appropriate directory
    mv -f /mysqlsetup.mod /opt/xcat/bin/mysqlsetup

    # Start supervisord to manage xCAT services
    /usr/bin/supervisord -c /etc/supervisord.conf

    # Display welcome message with available IP addresses
    cat /etc/motd
    HOSTIPS=$(ip -o -4 addr show up | grep -v "\<lo\>" | awk '{print $4}' | cut -d/ -f1)
    echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    echo "Welcome to Dockerized xCAT, please login with:"
    if [[ -n "$HOSTIPS" ]]; then
        for ip in $HOSTIPS; do
            echo "   ssh root@$ip -p 2200"
        done
        echo "The initial password is \"Rudra@@123\""
    fi
    echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"

    # Execute init process to start other system services
    exec /sbin/init
fi

