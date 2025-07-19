#!/bin/bash

set -e

# ================================
# Utility Functions
# ================================
log() {
    echo "[entrypoint] $*"
}

set_log_ownership() {
    if [[ -f /etc/debian_version ]]; then
        logadm="syslog:adm"
    else
        logadm="root:"
    fi
    chown -R "$logadm" /var/log/xcat/
}

load_xcat_environment() {
    source /etc/profile.d/xcat.sh
}

create_loop_devices() {
    log "Initializing loop devices..."
    for i in {0..7}; do
        [[ -b /dev/loop$i ]] || mknod /dev/loop$i -m0660 b 7 "$i"
    done
}

sync_xcat_config() {
    log "Creating symlink for /root/.xcat..."
    rsync -a /root/.xcat/ /xcatdata/.xcat
    rm -rf /root/.xcat
    ln -sf /xcatdata/.xcat /root/.xcat
}

configure_site_table() {
    log "Configuring xCAT site table..."

    XCATBYPASS=1 tabdump site | grep -q domain || \
        XCATBYPASS=1 chtab key=domain site.value="${DOMAIN}"

    XCATBYPASS=1 tabdump site | grep -q dhcpinterfaces || \
        XCATBYPASS=1 chtab key=dhcpinterfaces site.value="${DHCPINTERFACE}"

    XCATBYPASS=1 chtab key=master site.value="${MASTER}"
    XCATBYPASS=1 chtab key=nameservers site.value="${NAMESERVERS}"
    XCATBYPASS=1 chtab key=forwarders site.value="${FORWARDERS}"
}

configure_networks_table() {
    log "Configuring xCAT networks table..."

    if ! XCATBYPASS=1 tabdump networks | grep -q "ib0"; then
        XCATBYPASS=1 chdef -t network -o ib0 \
            net="${IB_Net}" mask="${IB_Mask}" gateway="${Xcatmaster}" \
            tftpserver="${Xcatmaster}" mgtifname=ib0 mtu=2044
    else
        log "Entry for ib0 already exists."
    fi

    XCATBYPASS=1 chdef -t network -o "${ObjectName}" \
        dhcpserver="${Dhcpserver}" gateway="${Gateway}" mask="${IP_Mask}" \
        mgtifname="${Mgtifname}" mtu=1500 net="${IP_Net}" tftpserver="${Tftpserver}"
}

initialize_xcat() {
    log "Initializing xCAT..."

    rsync -a /xcatdata.NEEDINIT/ /xcatdata
    mv /xcatdata.NEEDINIT /xcatdata.orig

    xcatconfig -d
    xcatconfig -i

    configure_site_table
    configure_networks_table
    sync_xcat_config
    create_loop_devices

    ln -sf /opt/xcat/bin/xcatclient /opt/xcat/probe/subcmds/bin/switchprobe
}

replace_mysqlsetup() {
    log "Replacing mysqlsetup with modified version..."
    mv -f /mysqlsetup.mod /opt/xcat/bin/mysqlsetup
}

start_services() {
    log "Starting supervisord..."
    /usr/bin/supervisord -c /etc/supervisord.conf
}

display_welcome() {
    cat /etc/motd
    HOSTIPS=$(ip -o -4 addr show up | grep -v "\<lo\>" | awk '{print $4}' | cut -d/ -f1)

    echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    echo "Welcome to Dockerized xCAT. You can login with:"
    for ip in $HOSTIPS; do
        echo "   ssh root@$ip -p 2200"
    done
    echo "The initial password is \"Rudra@@123\""
    echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
}

# ================================
# Main
# ================================
main() {
    set_log_ownership
    load_xcat_environment

    if [[ -d "/xcatdata.NEEDINIT" ]]; then
        initialize_xcat
    fi

    replace_mysqlsetup
    start_services
    display_welcome

    exec /sbin/init
}

main "$@"
