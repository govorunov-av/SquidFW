#!/bin/bash
##### BEGIN CHANGEABLE VARS #####

##### BASE VARS #####
PROXY_IP=''
PROXY_PORT=''
PROXY_LOGIN=''
PROXY_PASSWORD=''
HOME_NET='' #With prefix (ex: 192.168.100.0/24)
INTERNAL_NET='10.1.0.0/24' #ONLY /24 PREFIX

##### KEEPALIVED VARS #####
KEEPALIVED=0 #Set 0 or 1 for install vrrp service
KEEPALIVED_MASTER=1 #Set 0 or 1 for vrrp master (main node)
KEEPALIVED_VIP=192.168.100.254 #HA ip
KEEPALIVED_PASSWORD=changeme #Password for link Backup node

##### DOMAINS VARS #####
RU_SITES="
#Here you can write domain coming from the domains of the vpn_sites
#EXAMPLE: You write .com domain in vpn_sites and here you write .avito.com, this domains will be use default gateway
.vk.com
.habr.com" 

VPN_SITES="
.2ip.ru
.com"

##### LINK VARS #####
SQUID_LINK='https://github.com/govorunov-av/SquidFW/raw/refs/heads/main/squid-6.10-alt1.x86_64.rpm'
SQUID_HELPER_LINK='https://github.com/govorunov-av/SquidFW/raw/refs/heads/main/squid-helpers-6.10-alt1.x86_64.rpm'

##### END CHANGEABLE VARS #####

NET_INTERFACE=$(ip route get 1.1.1.1 | awk '{print$5; exit}')
NET_IP=$(ip -br a | grep $(echo ^$NET_INTERFACE) | awk '{print$3}' | cut -d/ -f1)
GATEWAY=$(ip r | grep default | grep $NET_INTERFACE | awk '{print$3}')
REDSOCKS_IP=$(echo $INTERNAL_NET | cut -d / -f1 | awk -F. '{print $1 "." $2 "." $3 ".1"}')

apt-get update && apt-get install git curl wget make gcc libevent-devel -y 
mkdir /build && cd /build
echo "Install and configure redsocks"
git clone https://github.com/darkk/redsocks.git
cd /build/redsocks/
make 
cp redsocks /usr/local/bin/redsocks 
echo "Create redsocks_proxy.conf"
cat << EOF > /etc/redsocks_proxy.conf
base {
        log_debug = off;
        log_info = on;
        log = "syslog:daemon";
        daemon = on;
        user = redsocks;
        group = redsocks;
        redirector = iptables;
}

redsocks {
        local_ip = 0.0.0.0;
        local_port = 12345;
        ip = $PROXY_IP;
        port = $PROXY_PORT;
        type = socks5;
        login = "$PROXY_LOGIN";
        password = "$PROXY_PASSWORD";
}
EOF
echo "Create redsocks run script"
mkdir /scripts

cat << EOF > /scripts/redsocks.sh
#!/bin/bash
/usr/local/bin/redsocks -c /etc/redsocks_proxy.conf

sleep 1
#Целевой IP-адрес
TARGET_IP=$PROXY_IP

#Функция проверки IP
check_ip() {
    CURRENT_IP=\$(curl -s ifconfig.me --max-time 2 --interface $REDSOCKS_IP)

    # Сравнение текущего IP с целевым
    if [[ \$CURRENT_IP != \$TARGET_IP ]]; then
    CURRENT_IP2=\$(curl -s ifconfig.me --max-time 5 --interface $REDSOCKS_IP)
    if [[ \$CURRENT_IP2 != \$TARGET_IP ]]; then

        ((COUNTER1++))

        if [ "$KEEPALIVED" == 1 ]; then
        echo \$COUNTER1 > /scripts/vrrp_counter
        fi

        echo "IP не совпадает. IP = \$CURRENT_IP. Перезапуск №: $COUNTER1. Перезапускаем redsocks..."
        pkill redsocks
        sleep 3
        /usr/local/bin/redsocks -c /etc/redsocks_proxy.conf &
    fi
    else
        echo "IP совпадает: \$CURRENT_IP"
        COUNTER1=0
		if [ "$KEEPALIVED" == 1 ]; then
			echo \$COUNTER1 > /scripts/vrrp_counter
        fi
    fi
}

while true; do
    check_ip
    sleep 35  # Пауза в 35 секунд
done
EOF

echo "Create redsocks service"
cat << EOF > /etc/systemd/system/redsocks.service
[Unit]
Description=Redsocks - Transparent Socks Redirector
After=network.target

[Service]
ExecStart=bash /scripts/redsocks.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

useradd redsocks 
usermod -aG redsocks redsocks
chown redsocks:redsocks /etc/redsocks_proxy.conf
chmod 770 /etc/redsocks_proxy.conf

echo "Install and configure squid"
mkdir /build/squid && cd /build/squid
wget $SQUID_LINK # Пересобранный пакет squid
wget $SQUID_HELPER_LINK  # Пересобранный пакет squid-helpers (Автоматически генерируется при сборке squid)
apt-get install squid -y #Установка squid, только ради зависимостей
apt-get remove squid -y #Удаление squid, но зависимости оставляем
apt-get install squid-6.10-alt1.x86_64.rpm -y && apt-get install squid-helpers-6.10-alt1.x86_64.rpm -y 

echo "Create base config for squid"
cat << EOF > /etc/squid/squid.conf
http_port 3228
http_port 3128 intercept #intercept http port
https_port 3129 intercept ssl-bump options=ALL:NO_SSLv3 connection-auth=off cert=/etc/squid/ssl_cert/squidCA.pem #intercept https port
always_direct allow all
sslproxy_cert_error allow all
acl step1 at_step SslBump1
ssl_bump peek step1
ssl_bump splice all
sslcrtd_program /usr/lib/squid/security_file_certgen -s /var/spool/squid/ssl_db -M 4MB

acl localnet src $HOME_NET
acl localnet src $INTERNAL_NET
acl ru_sites dstdomain "/etc/squid/ru_sites"
acl vpn_sites dstdomain "/etc/squid/vpn_sites"
acl all_domain dstdomain .*

tcp_outgoing_address $NET_IP ru_sites
tcp_outgoing_address $REDSOCKS_IP vpn_sites
tcp_outgoing_address $NET_IP all_domain

http_access allow localnet
http_access deny all

access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
cache_mem 128 MB
maximum_object_size_in_memory 512 KB
maximum_object_size 1024 KB
cache_dir aufs /opt/squid 1000 16 256
EOF

echo "Creating CA certificate"
mkdir /etc/squid/ssl_cert
openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -extensions v3_ca -keyout /etc/squid/ssl_cert/squid.key -out /etc/squid/ssl_cert/squid.crt -subj "/C=US/ST=State/L=City/O=Organization/OU=Department/CN=bfdscbvwrdvc.locedaq"
cat /etc/squid/ssl_cert/squid.key > /etc/squid/ssl_cert/squidCA.pem && cat /etc/squid/ssl_cert/squid.crt >> /etc/squid/ssl_cert/squidCA.pem
/usr/lib/squid/security_file_certgen -c -s  /var/spool/squid/ssl_db -M 4MB
mkdir /opt/squid # squid cache dir 
chown -R squid:squid /opt/squid && chmod 770 /opt/squid
squid -z

echo "Configure ru domains file"
echo "$RU_SITES" > /etc/squid/ru_sites

echo "Configure vpn domains file"
echo "$VPN_SITES" > /etc/squid/vpn_sites

IP_FORWARD=$(cat /etc/net/sysctl.conf | grep 'net.ipv4.ip_forward = 0' | wc -l )
if [ "$IP_FORWARD" -eq 1 ]; then
echo "enable ip_forvard"
sed -i 's/^net\.ipv4\.ip_forward = 0$/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf
fi

echo "Configure rt_tables"

cat << EOF > /etc/iproute2/rt_tables
255     local
254     main
253     default
200     redsocks_proxy_table
150     "$NET_INTERFACE"_table
0       unspec
EOF

echo "Configure network service"

cat << EOF > /scripts/custom-network.sh
ip link add link $NET_INTERFACE name redsocks_proxy type macvlan mode bridge
ip addr add ${REDSOCKS_IP}/24 dev redsocks_proxy
ip link set redsocks_proxy up
ip route add $HOME_NET dev $NET_INTERFACE src $NET_IP table ${NET_INTERFACE}_table
ip route add default via $GATEWAY dev $NET_INTERFACE table ${NET_INTERFACE}_table metric 100
ip route add $INTERNAL_NET dev redsocks_proxy src $REDSOCKS_IP table redsocks_proxy_table
ip route add default via $REDSOCKS_IP dev redsocks_proxy table redsocks_proxy_table metric 200
ip rule add from ${NET_IP}/32 table ${NET_INTERFACE}_table
ip rule add from ${REDSOCKS_IP}/32 table redsocks_proxy_table

iptables -F
iptables -t nat -F

iptables -t nat -N REDSOCKS
iptables -t nat -A REDSOCKS -d 0.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS -d 10.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS -d 169.254.0.0/16 -j RETURN
iptables -t nat -A REDSOCKS -d 172.16.0.0/12 -j RETURN
iptables -t nat -A REDSOCKS -d 192.168.0.0/16 -j RETURN
iptables -t nat -A REDSOCKS -d 224.0.0.0/4 -j RETURN
iptables -t nat -A REDSOCKS -d 240.0.0.0/4 -j RETURN
# Redirect from redsocks_proxy if to redsocks
iptables -t nat -A REDSOCKS -p tcp --dport 80 -j REDIRECT --to-ports 12345
iptables -t nat -A REDSOCKS -p tcp --dport 8080 -j REDIRECT --to-ports 12345
iptables -t nat -A REDSOCKS -p tcp --dport 443 -j REDIRECT --to-ports 12345
# Redirect from iif to squid
iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination $NET_IP:3129
iptables -t nat -A PREROUTING -p tcp --dport 8443 -j DNAT --to-destination $NET_IP:3129
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination $NET_IP:3128
iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination $NET_IP:3128

iptables -t nat -A PREROUTING -p tcp -s $REDSOCKS_IP -j REDSOCKS
iptables -t nat -A OUTPUT -p tcp -s $REDSOCKS_IP -j REDSOCKS

systemctl restart redsocks
systemctl restart squid
EOF

cat << EOF > /etc/systemd/system/custom-network.service
[Unit]
After=network.target

[Service]
ExecStart=bash /scripts/custom-network.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

if [ "$KEEPALIVED" == 1 ]; then
apt-get install keepalived -y

echo "Create redsocks checker script"

cat << EOF > /scripts/keepalived.sh
#!/bin/bash
COUNTER1=\$(cat /scripts/vrrp_counter)
if [ "\$COUNTER1" -ge 4 ]; then 
        exit 1
else
        exit 0
fi
EOF

chmod 770 /scripts/keepalived.sh

if [ "$KEEPALIVED_MASTER" == 1 ]; then
cat << EOF > /etc/keepalived/keepalived.conf
! Configuration File for keepalived
global_defs {
    enable_script_security
}

vrrp_script proxy_check {
    script "/scripts/keepalived.sh"
    interval 3
    user root
    weight -60
}

vrrp_instance redsocks {
    state MASTER
    interface $NET_INTERFACE
    virtual_router_id 254
    priority 100
    advert_int 2
    authentication {
        auth_type PASS
        auth_pass $KEEPALIVED_PASSWORD
    }
    virtual_ipaddress {
        $KEEPALIVED_VIP
    }
    track_script {
        proxy_check
    }
}
EOF
systemctl enable --now keepalived.service
else
cat << EOF > /etc/keepalived/keepalived.conf
global_defs {
    enable_script_security
}

vrrp_script proxy_check {
    script "/scripts/keepalived.sh"
    interval 3
    user root
}

vrrp_instance redsocks {
    state BACKUP
    interface $NET_INTERFACE
    virtual_router_id 254
    priority 50
    advert_int 2
    preempt
    preempt_delay 2
    authentication {
        auth_type PASS
        auth_pass $KEEPALIVED_PASSWORD
    }
    virtual_ipaddress {
        $KEEPALIVED_VIP
        
    }
    track_script {
        proxy_check
    }
}
EOF
systemctl enable --now keepalived.service
fi
fi
cd ~
rm -rf /build
systemctl daemon-reload
systemctl enable --now custom-network
echo "For normal work need reboot machine"