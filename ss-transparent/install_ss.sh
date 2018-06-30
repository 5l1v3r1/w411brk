#!/bin/bash

YELLOW='\033[0;33m'
RED='\033[0;31m'
END='\033[0m'

check_root() {
    if [ ! "$(id -u)" -eq 0 ]; then
        echo -e "$RED[-] You must be root$END"
        exit 1
    fi
}

install_ss() {
    echo -e "$YELLOW[*] Installing Shadowsocks$END"
    apt-get install shadowsocks-libev -y
    if [ ! -x "/usr/bin/ss-redir" ]; then
        echo -e "$RED[-]Shadowsocks not installed$END"
        exit 1
    fi

    # input your ss config
    echo -ne "$YELLOW[?] Your shadowsocks server ip: $END"
    read -r server_ip
    echo -ne "$YELLOW[?] Your server port: $END"
    read -r server_port
    echo -ne "$YELLOW[?] Your password: $END"
    read -r pass
    echo -ne "$YELLOW[?] Your encryption method: $END"
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
    echo -e "$YELLOW[*] Installing DNSOverHTTPS$END"
    tar xvzpf dot.tgz
    cd ./dns-over-https || return
    make install
    cd ..
    cp ./doh-client.conf /etc/dns-over-https
}

dns_config() {
    install_dot
    echo -e "$YELLOW[*] Configuring DNSOverHTTPS$END"
    systemctl disable systemd-resolved
    systemctl stop systemd-resolved

    # dnsmasq service
    apt-get install dnsmasq -y
    if ! grep "server=127.0.0.1#53535" /etc/dnsmasq.conf >/dev/null 2>&1; then
        echo -e "server=127.0.0.1#53535" >>/etc/dnsmasq.conf
    fi
    systemctl enable dnsmasq.service
    systemctl restart dnsmasq.service

    # dns over https service
    systemctl restart doh-client.service
    systemctl enable doh-client.service
}

main() {
    check_root

    git clone git@gitlab.com:jm33-m0/w411brk.git
    cd w411brk/ss-transparent || return

    # install ipset
    apt-get install ipset -y

    # ss config under /etc
    tar xvpf ss_config.tgz -C /

    install_ss

    # ss service
    cp ./ss-redir@.service /lib/systemd/system/ss-redir@.service &&
        systemctl daemon-reload

    # get DNS ready
    dns_config

    # start service
    echo -e "$YELLOW[*] Starting SS service$END"
    systemctl start ss-redir@config.service
    systemctl enable ss-redir@config.service
}

main
