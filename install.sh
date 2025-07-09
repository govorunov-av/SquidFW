##### BEGIN CHANGEABLE VARS #####
##### REQUIRED VARS #####
HOME_NET=''
INTERNAL_NET='' #ONLY /24 PREFIX
NODE_TYPE= #1 for single install, 2 for vrrp Master, 3 for vrrp Backup, 4 for LoadBalancer, 5 for ClamAv network antivirus
SQUID_LINK='https://github.com/govorunov-av/SquidFW/raw/refs/heads/main/squid-6.10-alt1.x86_64.rpm'
SQUID_HELPER_LINK='https://github.com/govorunov-av/SquidFW/raw/refs/heads/main/squid-helpers-6.10-alt1.x86_64.rpm'
RSYSLOG_INSTALL= #Set 1 or 0
RSYSLOG_COMMAND=''
##########

##### VARS FOR 1,2,3 NODES TYPE #####
PROXY_IP=
PROXY_PORT=
PROXY_LOGIN=
PROXY_PASSWORD=
RU_SITES="
"
VPN_SITES="
"
##########

##### VARS FOR 2,3,4 NODES TYPE #####
KEEPALIVED_VIP= #HA ip
KEEPALIVED_PASSWORD= #Password for link Backup nodes
#####SET LB_SERVER and CONSUL_ENCRYPT FOR 3 NODE TYPE, if need to connect to node 4 type
LB_SERVER=
CONSUL_ENCRYPT=''
##########

#### VARS FOR 5 NODE TYPE ####
NEW_GATEWAY=
########
##### END CHANGEABLE VARS #####

NET_INTERFACE=$(ip route get 1.1.1.1 | awk '{print$5; exit}')
NET_IP=$(ip -br a | grep $(echo ^$NET_INTERFACE) | awk '{print$3}' | cut -d/ -f1)
GATEWAY=$(ip r | grep default | grep $NET_INTERFACE | awk '{print$3}')
REDSOCKS_IP=$(echo $INTERNAL_NET | cut -d / -f1 | awk -F. '{print $1 "." $2 "." $3 ".1"}')

if [ $NODE_TYPE == 1 ]; then
KEEPALIVED=0
SQUID_LB=0
fi
if [ $NODE_TYPE == 2 ]; then
KEEPALIVED=1
KEEPALIVED_MASTER=1
if [ $KEEPALIVED_PRIORITY == "" ]; then
KEEPALIVED_PRIORITY=150
fi
SQUID_LB=0
fi
if [ $NODE_TYPE == 3 ]; then
KEEPALIVED=1
KEEPALIVED_MASTER=0
SQUID_LB=0
CONSUL_INSTALL=1
CONSUL_MASTER=0
fi
if [ $NODE_TYPE == 4 ]; then
KEEPALIVED=1
KEEPALIVED_MASTER=1
SQUID_LB=1
CONSUL_INSTALL=1
CONSUL_MASTER=1
fi
if [ $NODE_TYPE == 5 ]; then
KEEPALIVED=0
KEEPALIVED_MASTER=0
SQUID_LB=0
CONSUL_INSTALL=0
CONSUL_MASTER=0
fi

squid_lb () {
CACHE_MEM=$(echo $(free -h  | grep Mem | awk '{print$2}' | awk -F "M" '{print$1}' | awk -F "G" '{print$1}')*1024*0.78/1 | bc )
CACHE_DISK=$(echo $(df -h | grep "/$" | awk '{print$4}' | awk -F "G" '{print$1}')*1024/2 | bc)
cat << EOF > /etc/squid/squid.conf
http_port 3328
http_port 3028 intercept
https_port 3029 intercept ssl-bump options=ALL:NO_SSLv3 connection-auth=off cert=/etc/squid/ssl_cert/squidCA.pem #intercept https port
sslproxy_cert_error allow all
acl step1 at_step SslBump1
ssl_bump peek step1
ssl_bump splice all
sslcrtd_program /usr/lib/squid/security_file_certgen -s /var/spool/squid/ssl_db -M 4MB

access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log

acl localnet src $HOME_NET
acl localnet src $INTERNAL_NET
http_access allow localnet
http_access deny all

never_direct allow all

cache_mem $CACHE_MEM MB
maximum_object_size_in_memory 1 MB
maximum_object_size 10 MB
cache_dir ufs /opt/squid $CACHE_DISK 16 256
EOF

cat << EOF > /scripts/peer_install.sh
squid_peers () {
SERVERS_COUNT=\$(consul members | grep client | awk '{print\$2}' | awk -F ":" '{print\$1}' | wc -l)
MEMBERS=\$(consul members | grep client | grep alive | awk '{print\$2}' | awk -F ":" '{print\$1}')
if [ \$SERVERS_COUNT == 0 ]; then
echo EREROR, consul members = 0
exit 1
else
> /scripts/squid_peers
for ((i=1;i<=\$SERVERS_COUNT;i++)); do
IP=\$(echo \$MEMBERS | awk \\{print\\$\$i\\})
WEIGHT=\$(consul kv get squid/clients/\$IP/weight)
declare "SRV_IP_\$i"="\$IP"
declare "SRV_WEIGHT_\$i"="\$WEIGHT"
done
for ((i=1;i<=\$SERVERS_COUNT;i++)); do
SRV_IP="SRV_IP_\$i"
SRV_WEIGHT="SRV_WEIGHT_\$i"
STATUS=\$(curl -s http://192.168.16.1:8500/v1/health/checks/redsocks | jq ".[] | select(.ServiceTags | index(\\"\${!SRV_IP}\\"))" | grep critical | wc -l)
if [ \$STATUS == 0 ]; then
cat << EOF1 >> /scripts/squid_peers
cache_peer \${!SRV_IP} parent 3228 0 no-digest round-robin weight=\${!SRV_WEIGHT} name=proxy_\$i
cache_peer_access proxy_\$i allow localnet
EOF1
else
echo ERROR, node \${!SRV_IP} in critical status
fi
done
fi

OLD_PEERS=\$(cat /etc/squid/squid.conf | grep cache_peer)
NEW_PEERS=\$(cat /scripts/squid_peers | grep cache_peer)

if [ "\$NEW_PEERS" == "\$OLD_PEERS" ]; then
echo "Конфигурации пиров идентичны"
echo \$OLD_PEERS
else
echo "Конфигурации пиров отличаются"
echo "Новая конфигурация пиров: \$NEW_PEERS"
cp /etc/squid/squid.conf /scripts/squid.conf.old
sed -i '/cache_peer/d' /etc/squid/squid.conf
cat /scripts/squid_peers >> /etc/squid/squid.conf
echo "squid.service reloading .."
systemctl reload squid.service
SQUID_STATUS=\$(systemctl status squid | grep Active | awk '{print\$2}')
if [[ \$SQUID_STATUS == "failed" ]]; then
systemctl restart squid.service
sleep 10
SQUID_STATUS_NEW=\$(systemctl status squid | grep Active | awk '{print\$2}')
if [[ \$SQUID_STATUS_NEW == "failed" ]]; then
echo ERROR, SQUID in FAILED status, use old conf
cp /scripts/squid.conf.old /etc/squid/squid.conf
sleep 1
systemctl restart squid
fi
fi
fi
}
while true; do
squid_peers
sleep 10
done
EOF

cat << EOF > /etc/systemd/system/squid_peer.service
[Unit]
Description=Auto configuring squid peers
After=network.target

[Service]
ExecStart=bash /scripts/peer_install.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

}
consul_install () {
apt-get install consul jq -y
mkdir -p /scripts/consul/
cat << EOF > /scripts/consul/consul.sh
consul agent -config-file /scripts/consul/consul.json
EOF

cat << EOF > /etc/systemd/system/consul.service
[Unit]
Description=Consul client service
After=network.target

[Service]
ExecStart=bash /scripts/consul/consul.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
}
consul_worker () {
HOSTNAME=$(hostname)
if [[ $NODE_TYPE == 5 ]]; then
CONSUL_SRVC_NAME=clamav
else
CONSUL_SRVC_NAME=redsocks
fi
cat << EOF > /scripts/consul/consul.json
{
  "datacenter": "squidfw1",
  "server": false,
  "node_name": "$HOSTNMAME",
  "data_dir": "/scripts/consul",
  "bind_addr": "$NET_IP",
  "encrypt": "$CONSUL_ENCRYPT",
  "client_addr": "0.0.0.0",
  "retry_join": ["$LB_SERVER"],
  "log_level": "info",
  "enable_local_script_checks": true,
  "Service": {
    "name": "$CONSUL_SRVC_NAME",
    "tags": ["$HOSTNAME","$NET_IP"],
    "meta": {
      "hostname": "$HOSTNAME"
    },
    "Check": {
      "ScriptArgs": ["/scripts/consul_check.sh"],
      "interval": "10s",
      "timeout": "3s"
    }
  }
}
EOF

if [[ $NODE_TYPE == 5 ]]; then
sed -i 's|"server": false,|"server": true,|' /scripts/consul/consul.json
cat << EOF > /scripts/consul_check.sh
#!/bin/bash
STATUS=\$(echo "PING" | nc -U /var/run/clamav/clamd.sock 2>/dev/null)
if [[ "\$STATUS" != *"PONG"* ]]; then
	echo \$(date) \| "clamd не отвечает на PING"
    exit 2
fi
exit 0
EOF
chmod +x /scripts/consul_check.sh
else
cat << EOF > /scripts/consul_check.sh
#!/bin/bash
COUNTER1=\$(cat /scripts/vrrp_counter)
if [ "\$COUNTER1" -ge 2 ]; then
        exit 2
else
        exit 0
fi
EOF

apt-get install speedtest-cli -y
cat << EOF > /scripts/speedtest.sh
#!/bin/bash
for i in {1..3}; do
SPEEDTEST=\$(/usr/bin/speedtest-cli --source $REDSOCKS_IP --simple 2>&1)
EXIT=\$(echo \$SPEEDTEST | grep -c ERROR )
if [ \$EXIT -gt 0 ]; then
echo \$SPEEDTEST
else
DOWNLOAD=\$(echo \$SPEEDTEST | awk '{print\$5}')
UPLOAD=\$(echo \$SPEEDTEST | awk '{print\$8}')
SPEED=\$(echo "(\$DOWNLOAD + \$UPLOAD)" /2 | bc)
declare "SPEED\$i=\$(echo \$SPEED)"
fi
done
if [[ \$EXIT -gt 0 || \$SPEERD == 0 ]]; then
echo Error Exit or Speed = 0
else
AVERAGE=\$(echo "(\$SPEED1 + \$SPEED2 + \$SPEED3)" /3 | bc)
if [[ \$AVERAGE == "" || \$AVERAGE == 0 ]]; then
echo ERROR - AVERAGE SPEED = 0
else
consul kv put squid/clients/$NET_IP/weight \$AVERAGE
echo AVERAGE SPEED = \$AVERAGE
fi
fi
EOF

cat << EOF > /etc/systemd/system/weight_test.service
[Unit]
Description=Service for test proxy chanel
After=network.target

[Service]
ExecStart=bash /scripts/speedtest.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat << EOF > /etc/systemd/system/weight_test.timer
[Unit]
Description=Run speedtest

[Timer]
OnCalendar=*-*-* 0/5:0:0 

Persistent=true

[Install]
WantedBy=timers.target
EOF
chmod +x /scripts/{speedtest.sh,consul_check.sh}
chmod +x /scripts/consul/consul.sh

cat << EOF > /scripts/sites_importer.sh
files_changer () {
FILE_NAME="
ru_sites
vpn_sites"
FILE_PATH="squid/configs/"
FILES_COUNT=\$(echo \$FILE_NAME | wc -w)
for ((i=1;i<=\$FILES_COUNT;i++)); do
FILE=\$(echo \$FILE_NAME | awk \\{print\\$\$i\\})
FILE_STATUS=\$(consul kv get \${FILE_PATH}\${FILE} | wc -l)
echo consul kv get \${FILE_PATH}\${FILE}
if [ \$FILE_STATUS == 0 ]; then
echo "Config in consul empty, filling .."
consul kv put \${FILE_PATH}\${FILE} @/etc/squid/\$FILE
else
CONSUL_FILE=\$(consul kv get \${FILE_PATH}\${FILE})
LOCAL_FILE=\$(cat /etc/squid/\$FILE)
if [[ \$CONSUL_FILE == \$LOCAL_FILE ]]; then
echo "Consul and local file \$FILE equal"
else
echo "Consul and local file \$FILE not equal, copy consul file to local"
consul kv get \${FILE_PATH}\${FILE} > /etc/squid/\$FILE
systemctl reload squid
fi
fi
done
}
check_status () {
CONSUL_STATUS=\$(consul members | grep server | awk '{print\$3}')
if [[ \$CONSUL_STATUS == "alive" ]]; then
files_changer
else
echo "Consul main server failed, consul status = \$CONSUL_STATUS "
fi
}

while true; do
check_status
sleep 360
done
EOF
chmod +x /scripts/sites_importer.sh
cat << EOF > /etc/systemd/system/sitest_importer.service
[Unit]
Description=Checking sites files in consul and changing
After=network.target

[Service]
ExecStart=bash /scripts/sites_importer.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
cat << EOF > /scripts/priority_importer.sh 
#!/bin/bash
func () {
LOCAL_PRIORITY=\$(cat /etc/keepalived/keepalived.conf | grep priority | awk '{print\$2}')
CONSUL_PRIORITY=\$(consul kv get squid/clients/$NET_IP/priority)
STATUS=\$(consul kv get squid/clients/$NET_IP/priority 2>&1 | grep Error -c)
if [[ \$STATUS -ge 1 ]]; then
echo "Error, keepalived priority in consul empty, filling .."
consul kv put squid/clients/$NET_IP/priority \$LOCAL_PRIORITY
else
if [[ \$LOCAL_PRIORITY == \$CONSUL_PRIORITY ]]; then
echo Priority match
else
echo "Priority not match, filling .."
sed -i "s/priority [0-9]*/priority \$CONSUL_PRIORITY/" /etc/keepalived/keepalived.conf
fi
fi
}
while true; do
func
sleep 360
done
EOF
cat << EOF > /etc/systemd/system/priority_importer.service
[Unit]
Description=Checking priority in consul and changing in local if need
After=network.target

[Service]
ExecStart=bash /scripts/priority_importer.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
chmod +x /scripts/priority_importer.sh
fi
}
consul_master () {
if [[ ! -f /scripts/consul/consul.json ]]; then
CONSUL_ENCRYPT=$(consul keygen)
cat << EOF > /scripts/consul/consul.json
{
  "datacenter": "SquidFW1",
  "data_dir": "/opt/consul",
  "server": true,
  "encrypt": "$CONSUL_ENCRYPT",
  "bootstrap_expect": 1,
  "client_addr": "0.0.0.0",
  "bind_addr": "$NET_IP",
  "ui": true,
  "log_level": "INFO"
}
EOF
else
echo Consul master already installed, exporting CONSUL_ENCRYPT var
CONSUL_ENCRYPT=$(consul keyring -list | tail -n 1 | awk '{print$1}')
fi
}

redsocks_install () {
cd /build
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
    sleep 15
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
}
squid_install () { 
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

access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log
EOF
if [[ ! -f /etc/squid/ssl_cert/squidCA.pem  ]]; then
echo "Creating CA certificate"
RND_NUMBER=$(echo $((RANDOM % 900 + 100)))
mkdir /etc/squid/ssl_cert
openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 -extensions v3_ca -keyout /etc/squid/ssl_cert/squid.key -out /etc/squid/ssl_cert/squid.crt -subj "/C=US/ST=State/L=City/O=Organization/OU=Department/CN=squid_local_ca_$RND_NUMBER"
cat /etc/squid/ssl_cert/squid.key > /etc/squid/ssl_cert/squidCA.pem && cat /etc/squid/ssl_cert/squid.crt >> /etc/squid/ssl_cert/squidCA.pem
fi
/usr/lib/squid/security_file_certgen -c -s  /var/spool/squid/ssl_db -M 4MB
mkdir /opt/squid
chown -R squid:squid /opt/squid 
chmod 770 /opt/squid
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
EOF
if [[ $SQUID_LB != 1 ]]; then
cat << EOF >> /etc/iproute2/rt_tables
200     redsocks_proxy_table
150     ${NET_INTERFACE}_table
0       unspec
EOF
else
cat << EOF >> /etc/iproute2/rt_tables
150     ${NET_INTERFACE}_table
0       unspec
EOF
fi
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
#Redirect to squid
EOF
if [ $SQUID_LB == 1 ]; then
cat << EOF > /scripts/custom-network.sh
iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination $NET_IP:3029
iptables -t nat -A PREROUTING -p tcp --dport 8443 -j DNAT --to-destination $NET_IP:3029
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination $NET_IP:3028
iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination $NET_IP:3028
EOF
else
cat << EOF >> /scripts/custom-network.sh
iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination $NET_IP:3129
iptables -t nat -A PREROUTING -p tcp --dport 8443 -j DNAT --to-destination $NET_IP:3129
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination $NET_IP:3128
iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination $NET_IP:3128
EOF
fi

if [ $SQUID_LB != 1 ]; then
cat << EOF >> /scripts/custom-network.sh
iptables -t nat -A PREROUTING -p tcp -s $REDSOCKS_IP -j REDSOCKS
iptables -t nat -A OUTPUT -p tcp -s $REDSOCKS_IP -j REDSOCKS

systemctl restart redsocks
EOF
fi
cat << EOF >> /scripts/custom-network.sh
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
}

rsyslog () {
#install rsyslog client for centralized logging
apt-get install rsyslog-classic -y
echo "$RSYSLOG_COMMAND" > /etc/rsyslog.d/client.conf
sed -i 's/#ForwardToSyslog=no/ForwardToSyslog=yes/' /etc/systemd/journald.conf
systemctl enable --now rsyslog
}

clamav () {
apt-get update
apt-get install clamav c-icap-{clamav,devel} git make gcc libtool -y
cd /build
git clone https://github.com/govorunov-av/squidclamav.git
cd squidclamav
./configure
make
make install
libtool --finish /usr/lib64/c_icap/
cd -

mkdir /var/lib/c-icap/
chown -R _c_icap:_c_icap /var/lib/c-icap/

cat << EOF1 > /etc/c-icap.conf
PidFile /var/lib/c-icap/c-icap.pid
CommandsSocket /var/lib/c-icap/c-icap.ctl
Timeout 300
MaxKeepAliveRequests 100
KeepAliveTimeout 600
StartServers 1
MaxServers 20
MinSpareThreads     10
MaxSpareThreads     20
ThreadsPerChild     10
MaxRequestsPerChild 1000
Port 127.0.0.1:1344
TmpDir /var/tmp
MaxMemObject 131072
Pipelining on
SupportBuggyClients off
ModulesDir /usr/lib64/c_icap
ServicesDir /usr/lib64/c_icap
TemplateDir /usr/share/c_icap/templates/
TemplateDefaultLanguage en
LoadMagicFile /etc/c-icap.magic
RemoteProxyUsers off
RemoteProxyUserHeader X-Authenticated-User
RemoteProxyUserHeaderEncoded on
ServerLog /var/log/c-icap/server.log
AccessLog /var/log/c-icap/access.log
Service echo srv_echo.so
Service squid_clamav squidclamav.so
DebugLevel 1
EOF1
cat << EOF2 > /etc/clamav/clamd.conf
LogFile /var/log/clamav/clamd.log
PidFile /var/run/clamav/clamd.pid
DatabaseDirectory /var/lib/clamav/
LocalSocket /var/run/clamav/clamd.sock
FixStaleSocket yes
EOF2
cat << EOF3 > /etc/clamav/freshclam.conf
DatabaseDirectory /var/lib/clamav/
UpdateLogFile /var/log/clamav/freshclam.log
PidFile /var/run/clamav/freshclam.pid
DatabaseMirror packages.microsoft.com/clamav/
EOF3
cat << EOF4 > /etc/squidclamav.conf
maxsize 5M
#redirect http://pfSense.home.arpa/squid_clwarn.php
clamd_local /var/run/clamav/clamd.sock
timeout 1
logredir 0
dnslookup 0
safebrowsing 0
multipart 0
scan_mode ScanAllExcept
enable_libarchive 0
abortcontent ^video\/.*
abortcontent ^application\/x-mpegURL$
abortcontent ^application\/octet-stream$
abortcontent ^audio\/.*
abortcontent ^image\/.*
EOF4
cat << EOF5 > /etc/squid/squid.conf
http_port 3228
http_port 3128 intercept #intercept http port
https_port 3129 intercept ssl-bump options=ALL:NO_SSLv3 connection-auth=off cert=/etc/squid/ssl_cert/squidCA.pem #intercept https port
always_direct allow all
sslproxy_cert_error allow all

acl step1 at_step SslBump1
acl step2 at_step SslBump2
acl step3 at_step SslBump3

ssl_bump peek step1
ssl_bump bump all
http_upgrade_request_protocols OTHER allow all

sslcrtd_program /usr/lib/squid/security_file_certgen -s /var/spool/squid/ssl_db -M 4MB

acl localnet src $HOME_NET
acl all_domain dstdomain .*

tcp_outgoing_address $NET_IP all_domain

http_access allow localnet
http_access deny all

access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log

icap_enable on
icap_send_client_ip on
icap_send_client_username off
icap_client_username_encode off
icap_client_username_header X-Authenticated-User
icap_preview_enable on
icap_preview_size 1024

icap_service service_avi_req reqmod_precache icap://127.0.0.1:1344/squid_clamav bypass=off
adaptation_access service_avi_req allow all
icap_service service_avi_resp respmod_precache icap://127.0.0.1:1344/squid_clamav bypass=on
adaptation_access service_avi_resp allow all
icap_persistent_connections on
EOF5
cat << EOF6 > /etc/c-icap.magic
0:MZ:MSEXE:DOS/W32 executable/library/driver:EXECUTABLE
0:LZ:DOSEXE:MS-DOS executable:EXECUTABLE
0:\177ELF:ELF:ELF unix executable:EXECUTABLE
0:\312\376\272\276:JavaClass:Compiled Java class:EXECUTABLE
0:Rar!:RAR:Rar archive:ARCHIVE
0:PK\003\004:ZIP:Zip archive:ARCHIVE
0:PK00PK\003\004:ZIP:Zip archive:ARCHIVE
0:\037\213:GZip:Gzip compressed file:ARCHIVE
0:BZh:BZip:BZip compressed file:ARCHIVE
0:SZDD:Compress.exe:MS Copmress.exe'd compressed data:ARCHIVE
0:\037\235:Compress:UNIX compress:ARCHIVE
0:MSCF:MSCAB:Microsoft cabinet file:ARCHIVE
257:ustar:TAR:Tar archive file:ARCHIVE
0:\355\253\356\333:RPM:Linux RPM file:ARCHIVE
0:\170\237\076\042:TNEF:Transport Neutral Encapsulation Format:ARCHIVE
20:\xDC\xA7\xC4\xFD:ZOO:Zoo archiver:ARCHIVE
2:-lh:LHA:Lha archiver:ARCHIVE
0:ITSF:MSCHM:MS Windows Html Help:ARCHIVE
0:!<arch>\012debian:debian:Debian package:ARCHIVE
0:GIF8:GIF:GIF image data:GRAPHICS
0:BM:BMP:BMP image data:GRAPHICS
0:\377\330:JPEG:JPEG image data:GRAPHICS
0:\211PNG:PNG:PNG image data:GRAPHICS
0:\000\000\001\000:ICO:MS Windows icon resource:GRAPHICS
0:FWS:SWF:Shockwave Flash data:GRAPHICS
0:CWS:SWF:Shockwave Flash data:GRAPHICS
8:WEBP:WEBP:WEBP image data:GRAPHICS
4:ftypavif:AVIF:AV1 Image File Format:GRAPHICS
0:\000\000\001\263:MPEG:MPEG video stream:STREAM
0:\000\000\001\272:MPEG::STREAM
0:RIFF:RIFF:RIFF video/audio stream:STREAM
0:OggS:OGG:Ogg Stream:STREAM
0:ID3:MP3:MP3 audio stream:STREAM
0:\377\373:MP3:MP3 audio stream:STREAM
0:\377\372:MP3:MP3 audio stream:STREAM
0:\060\046\262\165\216\146\317:ASF:WMA/WMV/ASF:STREAM
0:.ra\0375:RAF:Real audio stream:STREAM
0:.RMF:RMF:Real Media File:STREAM
0:OggS:OGG:Ogg stream data:STREAM
8:AIFF:AIFF:AIFF audio data:STREAM
8:AIFC:AIFF:AIFF-C audio data:STREAM
8:8SVX:AIFF:IFF/8SVX audio data:STREAM
0:MOVI:SGI:SGI video format:STREAM
4:moov:QTFF:Quick time  video format:STREAM
4:mdat:QTFF:Quick time  video format:STREAM
4:wide:QTFF:Quick time  video format:STREAM
4:skip:QTFF:Quick time  video format:STREAM
4:free:QTFF:Quick time  video format:STREAM
8:isom:MP4:MP4 Apple video format:STREAM
8:mp41:MP4:MP4 Apple video format:STREAM
8:mp42:MP4:MP4 Apple video format:STREAM
8:mmp44:MP4:MP4 Apple video format:STREAM
8:M4A:MP4:MP4 Apple video format:STREAM
8:3gp:3GPP:3GPP Apple video format:STREAM
8:avc1:3GPP:3GPP Apple video format:STREAM
0:ICY 200 OK:ShouthCast:Shouthcast audio stream:STREAM
0:\320\317\021\340\241\261:MSOFFICE:MS Office Document:DOCUMENT
0:\376\067\0\043:MSOFFICE:MS Office Document:DOCUMENT
0:\333\245-\000\000\000:MSOFFICE:MS Office Document:DOCUMENT
0:\208\207\017\224\161\177\026\225\000:MSOFFICE::DOCUMENT
4:Standard Jet DB:MSOFFICE:MS Access Database:DOCUMENT
0:%PDF-:PDF:PDF document:DOCUMENT
0:%!:PS:PostScript document:DOCUMENT
0:\004%!:PS:PostScript document:DOCUMENT
EOF6
sed -i "s/Wants=clamav-freshclam-update.service//" /lib/systemd/system/{clamav-daemon.service,clamd.service}
sed -i "s/After=clamav-freshclam-update.service//" /lib/systemd/system/{clamav-daemon.service,clamd.service}
sed -i "s|ListenStream=/var/run/clamav/clamd.sock|ListenStream=/var/run/clamav/clamd.sock|" /lib/systemd/system/clamav-daemon.socket
cat << EOF7 > /etc/systemd/system/freshclamav.service
[Unit]

[Service]
ExecStart=bash /scripts/freshclam.sh
ExecReload=/bin/kill -USR2 $MAINPID
StandardOutput=syslog

[Install]
WantedBy=multi-user.target
EOF7

cat << EOF8 > /scripts/freshclam.sh
#!/bin/bash
freshclam
sleep 8h
EOF8

rm -rf /var/lib/clamav/freshclam.dat
touch /scripts/custom-network.sh
cat << EOF9 > /scripts/custom-network.sh
iptables -F
iptables -t nat -F
#Redirect to squid
iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination $NET_IP:3129
iptables -t nat -A PREROUTING -p tcp --dport 8443 -j DNAT --to-destination $NET_IP:3129
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination $NET_IP:3128
iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination $NET_IP:3128
EOF9

if [[ -n $NEW_GATEWAY ]]; then
echo "default via $NEW_GATEWAY" > /etc/net/ifaces/$NET_INTERFACE/ipv4route
fi
}

install () {
apt-get update && apt-get install git curl wget make gcc libevent-devel -y
mkdir /build
mkdir /scripts
squid_install
if [[ $SQUID_LB == 1 ]]; then
squid_lb
else
if [[ $NODE_TYPE == 5 ]]; then
:
else
redsocks_install
fi
fi
if [ $CONSUL_INSTALL == 1 ]; then
consul_install
if [ $CONSUL_MASTER == 1 ]; then
consul_master
systemctl enable --now consul
sleep 10
KEEPALIVED_PRIORITY=$(echo 255-5*$(consul members | grep server | wc -l) | bc)
consul kv put squid/clients/$NET_IP/priority $KEEPALIVED_PRIORITY
else
consul_worker
systemctl enable --now consul
cat << EOF >> /scripts/custom-network.sh
systemctl restart weight_test.service
systemctl restart weight_test.timer
systemctl restart sitest_importer.service
systemctl restart priority_importer.service
EOF
sleep 10
KEEPALIVED_PRIORITY=$(echo 250-5*$(consul members | wc -l) | bc)
consul kv put squid/clients/$NET_IP/priority $KEEPALIVED_PRIORITY
fi
fi

if [ "$KEEPALIVED" == 1 ]; then
apt-get install keepalived -y

echo "Create redsocks checker script"

cat << EOF > /scripts/keepalived.sh
#!/bin/bash
COUNTER1=\$(cat /scripts/vrrp_counter)
if [ "\$COUNTER1" -ge 2 ]; then
        exit 1
else
        exit 0
fi
EOF

echo "systemctl restart keepalived.service" >> /scripts/custom-network.sh
chmod 770 /scripts/keepalived.sh

if [ "$KEEPALIVED_MASTER" == 1 ]; then
cat << EOF > /etc/keepalived/keepalived.conf
! Configuration File for keepalived
global_defs {
    enable_script_security
}

EOF
if [ $SQUID_LB == 1 ]; then
cat << EOF >> /etc/keepalived/keepalived.conf
vrrp_script proxy_check {
    interval 3
    user root
}
EOF
cat << EOF >> /scripts/custom-network.sh
systemctl restart squid_peer.service
EOF
else
cat << EOF >> /etc/keepalived/keepalived.conf
vrrp_script proxy_check {
    script "/scripts/keepalived.sh"
    interval 3
    user root
    weight -60
}
EOF
fi
cat << EOF >> /etc/keepalived/keepalived.conf
vrrp_instance redsocks {
    state MASTER
    interface $NET_INTERFACE
    virtual_router_id 254
    priority $KEEPALIVED_PRIORITY
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
else
cat << EOF > /etc/keepalived/keepalived.conf
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
    state BACKUP
    interface $NET_INTERFACE
    virtual_router_id 254
    priority $KEEPALIVED_PRIORITY
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
fi
fi

if [ $RSYSLOG_INSTALL == 1 ]; then
rsyslog
fi

if [ $NODE_TYPE == 5 ]; then
clamav
sleep 5
systemctl enable consul
systemctl enable freshclamav
systemctl enable clamd
systemctl enable c-icap
systemctl enable squid
if [[ -n $LB_SERVER ]]; then
if [[ -n $CONSUL_ENCRYPT ]]; then
consul_install 
consul_worker
systemctl enable --now consul
else
	echo 'Переменная LB_SERVER определена, но CONSUL_ENCRYPT - нет, consul не будет установлен!'
fi
fi
fi

cd ~
rm -rf /build
systemctl daemon-reload
systemctl enable --now custom-network
systemctl restart custom-network
}
post_install () {
echo '###################################################################'
echo 'Установка завершена!'
if [ $CONSUL_MASTER == 1 ]; then
echo ON BACKUP NODE SET \$CONSUL_ENCRYPT=$CONSUL_ENCRYPT
fi
if [ $NODE_TYPE == 5 ]; then
echo 'ON CLIENT INSTALL TRUSTED CERT:'
cat /etc/squid/ssl_cert/squid.crt
fi
echo 'FOR WORK NEED REBOOT!'
}
install
post_install
