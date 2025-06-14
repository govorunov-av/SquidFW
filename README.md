Скрипт автоматической установки и настройки squid с поддержкой https и intercept. Squid будет распределять трафик по доменам на прокси и стандартный шлюз.


Так же, есть возможность настройки псевдо "кластера" из нескольких установок.


Варианты установки:

    1 - Простая установка squid и redsocks.
    2 - Установка squid с redsocks и keepalived (vrrp) в режиме Master.
    3 - Установка squid с redsocks и keepalived (vrrp) в режиме Backup.
    4 - Установка только squid в режиме только балансировки нагрузки на остальные ноды squid. (Используется cache_peer с weight, для равномерного распределения трафика на ноды с разными каналами прокси.
  
Вариант желаемой установки регулируется с помощью переменной NODE_TYPE.


Скрипт сделан под alt linux p10. Можно использовать alt jeos p10, распространяемый под лицензией GPL.


Так как для правильной работы squid, его необходимо пересобрать и пропатчить, прикрепил ссылки ниже, они помогут в этом. Либо же можно использовать мои пакеты из этого репозитория, по умолчанию они и используются. Для изменения этого - нужно дать переменным SQUID_LINK и SQUID_HELPER_LINK значение в виде ссылки на них.


Предполагаемая топология выглядит следующим образом:

![SquidFW_Diagram drawio](https://github.com/user-attachments/assets/d376611e-06a5-4595-8017-afa36e3e2a7c)


При установки в таком режиме ничего руками редактировать не придется, только указать верные переменные.


Перед запуском скрипт нужно изменить переменные, находящиеся в начале скрипта:

        ##### BEGIN CHANGEABLE VARS #####
        ##### REQUIRED VARS #####
        HOME_NET='192.168.0.0/16'
        INTERNAL_NET='10.1.0.0/24' #ONLY /24 PREFIX
        NODE_TYPE=3 #1 for single install, 2 for vrrp Master, 3 for vrrp Backup, 4 for LoadBalancer
        SQUID_LINK='https://github.com/govorunov-av/SquidFW/raw/refs/heads/main/squid-6.10-alt1.x86_64.rpm'
        SQUID_HELPER_LINK='https://github.com/govorunov-av/SquidFW/raw/refs/heads/main/squid-helpers-6.10-alt1.x86_64.rpm'
        ##########
        
        ##### VARS FOR 1,2,3 NODES TYPE #####
        PROXY_IP='123.123.123.123'
        PROXY_PORT='1234'
        PROXY_LOGIN='user123'
        PROXY_PASSWORD='pass123'
        RU_SITES="
        #Here you can write domain coming from the domains of the vpn_sites
        #EXAMPLE: You write .com domain in vpn_sites and here you write .habr.com, this domains will be use default gateway
        .habr.com"
        VPN_SITES="
        .com"
        ##########
        
        ##### VARS FOR 2,3,4 NODES TYPE #####
        KEEPALIVED_VIP=192.168.100.254 #HA ip
        KEEPALIVED_PASSWORD=123321123 #Password for link Backup nodes
        #SET LB_SERVER and CONSUL_ENCRYPT FOR 3 NODE TYPE, if need to connect to node 4 type
        LB_SERVER=192.168.11.1
        CONSUL_ENCRYPT='U1jGPtm9rduzZP5LK96g01T2H7QKFuYaPAXopCKZc=' #This value is issued after the installation of a type 4 node
        ##########
        ##### END CHANGEABLE VARS #####

Если собирать "кластер" с нодой в режиме 4, то количество "воркеров" может быть любым (как минимум 9 должно поддерживаться без вмешательства в сам скрипт).


Нода установленная в 4 режиме будет балансировать трафик в соответствии с weight каждого воркера. Weight устанавливается автоматически (с помощью speedtest-cli), может устанавливаться довольно долго (сервис запускается раз в 5 часов и переодически вылезает 403 ошибка), weight храниться в consul и его можно установить вручную. 

        consul kv put squid/clients/$NET_IP/weight 75


Так же keepalived priority устанавливается автоматически, при установки, и храниться в consul, можно изменить вручную. Важно помнить, что keepalived поддерживает значение приоритета от 1 до 255.

        consul kv put squid/clients/$NET_IP/priority 241

Consul мониторит ещё и работу redsocks (по curl ifconfig --interface $INTERNAL_NET_IP ), можно использовать web страницу consul`а для мониторинга. http://$LB_SERVER:8500
        
При желании "воркеров" можно упаковать в контейнер с пробросанным 3228 портом и запускать на ноде с любой ОС. Но придется использовать network=host и режим privileged. 


Для установки в 1 режиме можно использовать Dockerfile и сам скрипт из https://github.com/govorunov-av/SquidFW/tree/main/docker . Но vrrp там нет.


Links:

    https://habr.com/ru/articles/267851/
    https://habr.com/ru/articles/272733/
