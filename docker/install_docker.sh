#!/bin/bash
PROXY_IP=''
PROXY_PORT=''
PROXY_LOGIN=''
PROXY_PASSWORD=''
HOME_NET='' #ex 192.168.0.0/16
INTERNAL_NET='10.1.0.0/24' #ONLY /24 PREFIX

SQUID_LINK='https://github.com/govorunov-av/SquidFW/raw/refs/heads/main/squid-6.10-alt1.x86_64.rpm'
SQUID_HELPER_LINK='https://github.com/govorunov-av/SquidFW/raw/refs/heads/main/squid-helpers-6.10-alt1.x86_64.rpm'

NET_INTERFACE=$(ip route get 1.1.1.1 | awk '{print$5; exit}')
NET_IP=$(ip -br a | grep $(echo ^$NET_INTERFACE) | awk '{print$3}' | cut -d/ -f1)
GATEWAY=$(ip r | grep default | grep $NET_INTERFACE | awk '{print$3}')
REDSOCKS_IP=$(echo $INTERNAL_NET | cut -d / -f1 | awk -F. '{print $1 "." $2 "." $3 ".1"}')

apt-get update && apt-get install git curl wget make gcc libevent-devel iptables openssl -y 
mkdir /build && cd /build
echo "Install and configure redsocks"
git clone https://github.com/darkk/redsocks.git
cd /build/redsocks 
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
# Целевой IP-адрес
TARGET_IP=$PROXY_IP

# Функция проверки IP
check_ip() {
    CURRENT_IP=\$(curl -s ifconfig.me --max-time 2 --interface $REDSOCKS_IP)

    # Сравнение текущего IP с целевым
    if [[ \$CURRENT_IP != \$TARGET_IP ]]; then
    CURRENT_IP2=\$(curl -s ifconfig.me --max-time 5 --interface $REDSOCKS_IP)
    if [[ \$CURRENT_IP2 != \$TARGET_IP ]]; then
        echo "IP не совпадает. IP = \$CURRENT_IP. Перезапускаем redsocks..."
        pkill redsocks
        sleep 3
        /usr/local/bin/redsocks -c /etc/redsocks_proxy.conf &
    fi
    else
        echo "IP совпадает: \$CURRENT_IP"
    fi
}
while true; do
    check_ip
    sleep 35  # Пауза в 35 секунд
done
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

acl localnet src all
acl ru_sites dstdomain "/etc/squid/ru_sites"
acl vpn_sites dstdomain "/etc/squid/vpn_sites"
acl all_domain dstdomain .*

tcp_outgoing_address $NET_IP ru_sites
tcp_outgoing_address $REDSOCKS_IP vpn_sites
tcp_outgoing_address $NET_IP all_domain

#http_access deny ban_sites
http_access allow localnet
http_access deny all

access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
cache_mem 128 MB
maximum_object_size_in_memory 512 KB
maximum_object_size 1024 KB
cache_dir aufs /opt/squid 3000 16 256
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
cat << EOF > /etc/squid/ru_sites
.yandex.com
EOF

echo "Configure vpn domains file"
cat << EOF > /etc/squid/vpn_sites
.com
.2ip.ru
EOF

echo "Configure rt_tables"
echo '255     local' > /etc/iproute2/rt_tables
echo '254     main' >> /etc/iproute2/rt_tables
echo '253     default' >> /etc/iproute2/rt_tables
echo '200     redsocks_proxy_table' >> /etc/iproute2/rt_tables
echo "100     "$NET_INTERFACE"_table" >> /etc/iproute2/rt_tables
echo '0       unspec' >> /etc/iproute2/rt_tables

echo "Configure network service"

cat << EOF > /scripts/custom-network.sh
echo 'echo "App already installed"' > /squid/$0
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
iptables -t nat -A REDSOCKS -d 172.17.0.0/16 -j RETURN
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

sleep 1
service squid status
squid
sleep 1
squid 2> /dev/null
#sleep infinity
bash /scripts/redsocks.sh
EOF
echo "Configure resolv.conf"
echo "nameserver 1.1.1.1" > /etc/resolv.conf
