#!/bin/bash

YELLOW='\033[0;33m'
RED='\033[0;31m'
END='\033[0m'

check_root() {
    if [ ! "$(id -u)" -eq 0 ]; then
        echo -e "$RED [-] You must be root$END"
        exit 1
    fi
}

get_pkgmgr() {
    if [ -f /etc/os-release ]; then
        # freedesktop.org and systemd
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        # linuxbase.org
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        # For some versions of Debian/Ubuntu without lsb_release command
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        # Older Debian/Ubuntu/etc.
        OS=Debian
        VER=$(cat /etc/debian_version)
    elif [ -f /etc/SuSe-release ]; then
        # Older SuSE/etc.
        OS="$RED [-] Old SuSE$END"
    elif [ -f /etc/redhat-release ]; then
        # Older Red Hat, CentOS, etc.
        OS="$RED [-] Old RHEL$END"
    else
        # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
        OS=$(uname -s)
        VER=$(uname -r)
    fi

    echo -e "[*] You are using $YELLOW $OS $VER $END"

    if [ "$OS" = "Debian" ] || [ "$OS" = "Ubuntu" ]; then
        INSTALL='apt-get'
        INSTALL_ARG='install'
    elif [ "$OS" = "Arch Linux" ]; then
        INSTALL='pacman'
        INSTALL_ARG='-S'
    else
        if which dnf >/dev/null 2>&1; then
            INSTALL='dnf'
            INSTALL_ARG='install'
        elif which yum >/dev/null 2>&1; then
            INSTALL='yum'
            INSTALL_ARG='install'
        fi
    fi
    export INSTALL
    export INSTALL_ARG
    echo -e "[*] Using $YELLOW $INSTALL $INSTALL_ARG $END as package installer"
}

install_ss() {
    echo -e "$YELLOW [*] Installing Shadowsocks$END"
    "$INSTALL" "$INSTALL_ARG" shadowsocks-libev
    if [ ! -x "/usr/bin/ss-redir" ]; then
        echo -e "$RED [-]Shadowsocks not installed$END"
        exit 1
    fi

    # input your ss config
    echo -ne "$YELLOW [?] Your shadowsocks server ip: $END"
    read -r server_ip
    echo -ne "$YELLOW [?] Your server port: $END"
    read -r server_port
    echo -ne "$YELLOW [?] Your password: $END"
    read -r pass
    echo -ne "$YELLOW [?] Your encryption method: $END"
    read -r encryption

    # write to config file
    sed -i "s/1.1.1.1/$server_ip/g" /etc/shadowsocks-libev/ss_up.sh
    cat <<EOF >/etc/shadowsocks-libev/config.json
{
    "server": "$server_ip",
    "server_port": "$server_port",
    "password": "$pass",
    "method": "$encryption",
    "local_address": "127.0.0.1",
    "local_port": 54763,
    "timeout": 300,
    "reuse_port": true
}
EOF
}

install_dot() {
    echo -e "$YELLOW [*] Installing DNSOverHTTPS$END"
    tar xvzpf dot.tgz
    cd ./dns-over-https || return
    make install
    cd ..
    cp ./doh-client.conf /etc/dns-over-https
}

dns_config() {
    install_dot
    echo -e "$YELLOW [*] Configuring DNSOverHTTPS$END"
    systemctl disable systemd-resolved
    systemctl stop systemd-resolved

    # dnsmasq service
    "$INSTALL" "$INSTALL_ARG" dnsmasq

    cp -f ./dnsmasq.conf /etc
    systemctl enable dnsmasq.service
    systemctl restart dnsmasq.service

    # dns over https service
    systemctl restart doh-client.service
    systemctl enable doh-client.service
}

main() {
    check_root
    get_pkgmgr

    git clone https://github.com/jm33-m0/w411brk.git
    cd w411brk/ss-transparent || return

    # install ipset
    "$INSTALL" "$INSTALL_ARG" ipset

    # ss config under /etc
    tar xvpf ss_config.tgz -C /

    install_ss

    # ss service
    cp ./ss-redir@.service /lib/systemd/system/ss-redir@.service &&
        systemctl daemon-reload

    # get DNS ready
    dns_config

    # start service
    echo -e "$YELLOW [*] Starting SS service$END"
    systemctl start ss-redir@config.service
    systemctl enable ss-redir@config.service
}

main
