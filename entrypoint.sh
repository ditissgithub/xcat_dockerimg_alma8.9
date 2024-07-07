#! /bin/bash

is_ubuntu=$(test -f /etc/debian_version && echo Y)
[[ -z ${is_ubuntu} ]] && logadm="root:" || logadm="syslog:adm"
chown -R ${logadm} /var/log/xcat/
. /etc/profile.d/xcat.sh
if [[ -d "/xcatdata.NEEDINIT"  ]]; then
    echo "initializing xCAT ..."
    rsync -a /xcatdata.NEEDINIT/ /xcatdata
    mv /xcatdata.NEEDINIT /xcatdata.orig
    xcatconfig -d

    #echo "initializing networks table..."
    xcatconfig -i
    
    #Set the values of DOMAIN and DHCPINTERFACES if they are not already present, and provide their values along with the creation of service
    XCATBYPASS=1 tabdump site | grep domain || XCATBYPASS=1 chtab key=domain site.value=${DOMAIN}
    XCATBYPASS=1 tabdump site | grep dhcpinterfaces || XCATBYPASS=1 chtab key=dhcpinterfaces site.value=${DHCPINTERFACE}
    #Update the values of the keys {MASTER, NAMESERVERS, FORWARDERS}, providing the new values along with the creation of service
    XCATBYPASS=1 chtab key=master site.value=${MASTER}
    XCATBYPASS=1 chtab key=nameservers site.value=${NAMESERVERS}
    XCATBYPASS=1 chtab key=forwarders site.value=${FORWARDERS}

    echo "create symbol link for /root/.xcat..."
    rsync -a /root/.xcat/* /xcatdata/.xcat
    rm -rf /root/.xcat/
    ln -sf -t /root /xcatdata/.xcat

    echo "initializing loop devices..."
    # workaround for no loop device could be used by copycds
    for i in {0..7}
    do
        test -b /dev/loop$i || mknod /dev/loop$i -m0660 b 7 $i
    done
    # workaround for missing `switch_macmap` (#13)
    ln -sf /opt/xcat/bin/xcatclient /opt/xcat/probe/subcmds/bin/switchprobe
fi

## Start the xcatd service
restartxcatd &
pid=$!  # Get the process ID of restartxcatd
wait $pid  # Wait for restartxcatd to complete
##


cat /etc/motd
HOSTIPS=$(ip -o -4 addr show up|grep -v "\<lo\>"|xargs -I{} expr {} : ".*inet \([0-9.]*\).*")
echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
echo "welcome to Dockerized xCAT, please login with"
[[ -n "$HOSTIPS"  ]] && for i in $HOSTIPS; do echo "   ssh root@$i -p 2200  "; done && echo "The initial password is \"cluster\""
echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"


#read -p "press any key to continue..."
exec /sbin/init
