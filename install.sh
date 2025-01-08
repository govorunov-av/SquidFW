#!/bin/bash
PROXY_IP=''
PROXY_PORT=''
PROXY_LOGIN=''
PROXY_PASSWORD=''
HOME_NET='192.168.0.0/16'
INTERNAL_NET='10.1.0.0/24' #ONLY /24 PREFIX
INTERNAL_NET1='10.1.1.0/24' #ONLY /24 PREFIX
INSTALL_BYEDPI=1 # 1/0

SQUID_LINK='https://github.com/govorunov-av/SquidFW/raw/refs/heads/main/squid-6.10-alt1.x86_64.rpm'
SQUID_HELPER_LINK='https://github.com/govorunov-av/SquidFW/raw/refs/heads/main/squid-helpers-6.10-alt1.x86_64.rpm'

NET_INTERFACE=$(ip route get 1.1.1.1 | awk '{print$5; exit}')
NET_IP=$(ip -br a | grep $(echo ^$NET_INTERFACE) | awk '{print$3}' | cut -d/ -f1)
GATEWAY=$(ip r | grep default | grep $NET_INTERFACE | awk '{print$3}')
REDSOCKS_IP=$(echo $INTERNAL_NET | cut -d / -f1 | awk -F. '{print $1 "." $2 "." $3 ".1"}')
BYEDPI_IP=$(echo $INTERNAL_NET1 | cut -d / -f1 | awk -F. '{print $1 "." $2 "." $3 ".1"}')

BYEDPI_COMMAND='/usr/local/bin/ciadpi --split 8 --auto r --oob 2 -R 1-3 -Y -r 4 --md5sig --fake-data=":GET /HTTP/1.1\r\nHost: ya.ru\r\n\r\n" --fake -1 --disorder 3 --auto=torst' 

apt-get update && apt-get install git curl wget make gcc libevent-devel -y 
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

if [ "$INSTALL_BYEDPI" -eq 1 ]; then
cd /build
git clone https://github.com/hufrea/byedpi.git
cd /build/byedpi
make 
make install 
cp ciadpi /usr/local/bin/ciadpi
cat << EOF > /etc/redsocks_byedpi.conf
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
	local_port = 12346;
	ip = 127.0.0.1;
	port = 1080;
	type = socks5;
}
EOF
chown redsocks:redsocks /etc/redsocks_byedpi.conf
chmod 770 /etc/redsocks_byedpi.conf
cat << EOF > /scripts/byedpi.sh
$BYEDPI_COMMAND
EOF
fi

if [ "$INSTALL_BYEDPI" -eq 1 ]; then
INSTALL_BYEDPI_COMMAND='/usr/local/bin/redsocks -c /etc/redsocks_byedpi.conf'
fi

cat << EOF > /scripts/redsocks.sh
#!/bin/bash
/usr/local/bin/redsocks -c /etc/redsocks_proxy.conf
$INSTALL_BYEDPI_COMMAND

sleep 1
# Целевой IP-адрес
TARGET_IP=$PROXY_IP

# Функция проверки IP
check_ip() {
    CURRENT_IP=\$(curl -s ifconfig.me --max-time 3 --interface $REDSOCKS_IP)

    # Сравнение текущего IP с целевым
    if [[ \$CURRENT_IP != \$TARGET_IP ]]; then
        echo "IP не совпадает. IP = \$CURRENT_IP. Перезапускаем redsocks..."
        pkill redsocks
        /usr/local/bin/redsocks -c /etc/redsocks_proxy.conf &
    else
        echo "IP совпадает: \$CURRENT_IP"
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

echo "Create byedpi service"
cat << EOF > /etc/systemd/system/byedpi.service
[Unit]
After=network.target

[Service]
ExecStart=bash /scripts/byedpi.sh
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
acl vpn_sites dstdomain "/etc/squid/vpn_sites"
#acl ru_sites dstdomain "/etc/squid/ru_sites"
acl vpn_sites dstdomain "/etc/squid/vpn_sites"
#acl ban_sites src "/etc/squid/ban_sites"
acl all_domain dstdomain .*

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

echo "Configure vpn domains file"

cat << EOF > /etc/squid/vpn_sites
.com
EOF

IP_FORWARD=$(cat /etc/net/sysctl.conf | grep 'net.ipv4.ip_forward = 0' | wc -l )
if [ "$IP_FORWARD" -eq 1 ]; then
echo "enable ip_forvard"
sed -i 's/^net\.ipv4\.ip_forward = 0$/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf
fi

echo "Configure rt_tables"
echo '255     local' > /etc/iproute2/rt_tables
echo '254     main' >> /etc/iproute2/rt_tables
echo '253     default' >> /etc/iproute2/rt_tables
echo '200     redsocks_proxy_table' >> /etc/iproute2/rt_tables

if [ "$INSTALL_BYEDPI" -eq 1 ]; then
echo '150     redsocks_byedpi_table' >> /etc/iproute2/rt_tables
fi

echo "100     "$NET_INTERFACE"_table" >> /etc/iproute2/rt_tables
echo '0       unspec' >> /etc/iproute2/rt_tables

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
EOF

if [ "$INSTALL_BYEDPI" -eq 1 ]; then
cat << EOF >> /scripts/custom-network.sh
ip link add link $NET_INTERFACE name redsocks_byedpi type macvlan mode bridge
ip addr add ${BYEDPI_IP}/24 dev redsocks_byedpi
ip link set redsocks_byedpi up
ip route add $INTERNAL_NET1 dev redsocks_proxy src $BYEDPI_IP table redsocks_proxy_table
ip route add default via $BYEDPI_IP dev redsocks_byedpi table redsocks_byedpi_table metric 150
ip rule add from ${BYEDPI_IP}/32 table redsocks_byedpi_table
EOF
fi

cat << EOF >> /scripts/custom-network.sh
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

EOF

if [ "$INSTALL_BYEDPI" -eq 1 ]; then	
cat << EOF >> /scripts/custom-network.sh
iptables -t nat -N BYEDPI
iptables -t nat -A BYEDPI -d 0.0.0.0/8 -j RETURN
iptables -t nat -A BYEDPI -d 10.0.0.0/8 -j RETURN
iptables -t nat -A BYEDPI -d 127.0.0.0/8 -j RETURN
iptables -t nat -A BYEDPI -d 169.254.0.0/16 -j RETURN
iptables -t nat -A BYEDPI -d 172.16.0.0/12 -j RETURN
iptables -t nat -A BYEDPI -d 192.168.0.0/16 -j RETURN
iptables -t nat -A BYEDPI -d 224.0.0.0/4 -j RETURN
iptables -t nat -A BYEDPI -d 240.0.0.0/4 -j RETURN	

iptables -t nat -A BYEDPI -p tcp --dport 80 -j REDIRECT --to-ports 12346
iptables -t nat -A BYEDPI -p tcp --dport 8080 -j REDIRECT --to-ports 12346
iptables -t nat -A BYEDPI -p tcp --dport 443 -j REDIRECT --to-ports 12346

iptables -t nat -A PREROUTING -p tcp --dport 80 -s $REDSOCKS_IP -j DNAT --to-destination $BYEDPI_IP
iptables -t nat -A PREROUTING -p tcp --dport 8080 -s $REDSOCKS_IP -j DNAT --to-destination $BYEDPI_IP
iptables -t nat -A PREROUTING -p tcp --dport 443 -s $REDSOCKS_IP -j DNAT --to-destination $BYEDPI_IP
iptables -t nat -A PREROUTING -p tcp --dport 80 -s $NET_IP -j DNAT --to-destination $BYEDPI_IP
iptables -t nat -A PREROUTING -p tcp --dport 8080 -s $NET_IP -j DNAT --to-destination $BYEDPI_IP
iptables -t nat -A PREROUTING -p tcp --dport 443 -s $NET_IP -j DNAT --to-destination $BYEDPI_IP

iptables -t nat -A PREROUTING -p tcp -s $BYEDPI_IP -j BYEDPI
iptables -t nat -A OUTPUT -p tcp -s $BYEDPI_IP -j BYEDPI

EOF
fi

cat << EOF >> /scripts/custom-network.sh
systemctl restart byedpi
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

systemctl daemon-reload
systemctl enable --now custom-network
echo "For normal work need reboot machine"
