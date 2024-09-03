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
    #Set the values of DOMAIN and DHCPINTERFACES if they are not already present, and provide their values along with the creatio                                                                                                              n of service
    XCATBYPASS=1 tabdump site | grep domain || XCATBYPASS=1 chtab key=domain site.value=${DOMAIN}
    XCATBYPASS=1 tabdump site | grep dhcpinterfaces || XCATBYPASS=1 chtab key=dhcpinterfaces site.value=${DHCPINTERFACE}
    #Update the values of the keys {MASTER, NAMESERVERS, FORWARDERS}, providing the new values along with the creation of service
    XCATBYPASS=1 chtab key=master site.value=${MASTER}
    XCATBYPASS=1 chtab key=nameservers site.value=${NAMESERVERS}
    XCATBYPASS=1 chtab key=forwarders site.value=${FORWARDERS}
    # Add new entry in networks file if it does not exist
    if ! XCATBYPASS=1 tabdump networks | grep -q "ib0"; then
      XCATBYPASS=1 chdef -t network -o ib0 net="$IB_Net" mask="$IB_Mask" gateway="$Xcatmaster"  tftpserver="$Xcatmaster" mgtifnam                                                                                                              e=ib0 mtu=2044
    else
      echo "Entry for ib0 already exists."
    fi

    # Change the input value in networks file if the entry exists
    if XCATBYPASS=1 tabdump networks | grep -q "$ObjectName"; then
      XCATBYPASS=1 chdef -t network -o "$ObjectName" dhcpserver="$Dhcpserver" gateway="$Gateway" mask="$IP_Mask" mgtifname="$Mgti                                                                                                              fname" mtu=1500 net="$IP_Net" tftpserver="$Tftpserver"
    else
      XCATBYPASS=1 chdef -t network -o "$ObjectName" dhcpserver="$Dhcpserver" gateway="$Gateway" mask="$IP_Mask" mgtifname="$Mgti                                                                                                              fname" mtu=1500 net="$IP_Net" tftpserver="$Tftpserver"
    fi

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

##Move updated mysqlsetup perl file to /opt/xcat/bin/mysqlsetup

mv -f /mysqlsetup.mod /opt/xcat/bin/mysqlsetup

## Start the xcatd service
# Start supervisord
/usr/bin/supervisord -c /etc/supervisord.conf

cat /etc/motd
HOSTIPS=$(ip -o -4 addr show up|grep -v "\<lo\>"|xargs -I{} expr {} : ".*inet \([0-9.]*\).*")
echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
echo "welcome to Dockerized xCAT, please login with"
[[ -n "$HOSTIPS"  ]] && for i in $HOSTIPS; do echo "   ssh root@$i -p 2200  "; done && echo "The initial password is \"Rudra@@123                                                                                                              \""
echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"


#read -p "press any key to continue..."
exec /sbin/init

