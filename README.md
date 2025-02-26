
Отказоустойчивый прозрачный squid, с поддержкой https и балансирующий трафик по доменам. Определенные домены он отправляет на redsocks, остальное на default gateway.


Если необходимо более 2х объединенных нод, то придется немного править приоритет и вес (Убавляемый при неисправности прокси).

Скрипт сделан под alt linux p10. 

Так как для правильной работы squid, его необходимо пересобрать, прикрепил ссылки ниже, они помогут в этом. Либо же можно использовать мои пакеты, из этого репозитория, по умолчанию они и используются.


Предполагаемая топология выглядит следующим образом:

![{9C9DF2A8-6EFD-44F4-9BA1-A1A60E53E615}](https://github.com/user-attachments/assets/09e2f95d-4d50-4ba6-945c-1cc1e280d550)


Перед запуском скрипт нужно изменить переменные, находящиеся в начале скрипта, вот пример:

        ##### BEGIN CHANGEABLE VARS #####
        
        ##### BASE VARS #####
        PROXY_IP='1.2.3.4'
        PROXY_PORT='1234'
        PROXY_LOGIN='user'
        PROXY_PASSWORD='password'
        HOME_NET='192.168.0.0/16' #With prefix (ex: 192.168.100.0/24)
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

Links:

    https://habr.com/ru/articles/267851/
    https://habr.com/ru/articles/272733/
