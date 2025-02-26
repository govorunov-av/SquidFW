
Отказоустойчивый прозрачный squid, с поддержкой https и балансирующий трафик по доменам. Определенные домены он отправляет на redsocks, остальное на default gateway.


Если необходимо более 2х объединенных нод, то придется немного править приоритет и вес (Убавляемый при неисправности прокси).

Скрипт сделан под alt linux p10. 

Так как для правильной работы squid, его необходимо пересобрать, прикрепил ссылки ниже, они помогут в этом. Либо же можно использовать мои пакеты, из этого репозитория, по умолчанию они и используются.


Предполагаемая топология выглядит следующим образом:

![New draw io Diagram-176971 drawio](https://github.com/user-attachments/assets/b743adc7-8765-4ebb-ad82-aef79da37313)


Перед запуском скрипт нужно изменить переменные, находящиеся в начале скрипта:

        ##### BEGIN CHANGEABLE VARS #####
        
        ##### BASE VARS #####
        PROXY_IP='123.123.123.123'
        PROXY_PORT='12332'
        PROXY_LOGIN='user123321'
        PROXY_PASSWORD='123password321'
        HOME_NET='192.168.0.0/16'
        INTERNAL_NET='10.1.0.0/24' #ONLY /24 PREFIX
        
        NODE_TYPE=4 #1 for single install, 2 for vrrp Master, 3 for vrrp Backup, 4 for LoadBalancer
        
        ##### HA VARS #####
        KEEPALIVED_VIP=192.168.1.254 #HA ip
        KEEPALIVED_PASSWORD=123changeme321 #Password for link Backup nodes
        
        #ONLY ip and weight 2 or 3 type servers. After ":" set proxy speed (in Mbit/s)
        SERVERS_SOCK="
        192.168.16.2:70
        192.168.16.3:9
        "
        ##### DOMAINS VARS #####
        RU_SITES="
        #Here you can write domain coming from the domains of the vpn_sites
        #EXAMPLE: You write .com domain in vpn_sites and here you write .habr.com, this domains will be use default gateway
        .habr.com"
        
        VPN_SITES="
        .com"
        
        ##### LINK VARS #####
        SQUID_LINK='https://github.com/govorunov-av/SquidFW/raw/refs/heads/main/squid-6.10-alt1.x86_64.rpm'
        SQUID_HELPER_LINK='https://github.com/govorunov-av/SquidFW/raw/refs/heads/main/squid-helpers-6.10-alt1.x86_64.rpm'
        ##### END CHANGEABLE VARS #####

Links:

    https://habr.com/ru/articles/267851/
    https://habr.com/ru/articles/272733/
