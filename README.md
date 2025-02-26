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

![New draw io Diagram-176971 drawio](https://github.com/user-attachments/assets/b743adc7-8765-4ebb-ad82-aef79da37313)


При установки в таком режиме ничего руками редактировать не придется, только указать верные переменные.


Перед запуском скрипт нужно изменить переменные, находящиеся в начале скрипта:

        ##### BEGIN CHANGEABLE VARS #####
        
        ##### BASE VARS #####
        PROXY_IP='123.123.123.123'
        PROXY_PORT='12332'
        PROXY_LOGIN='user123321'
        PROXY_PASSWORD='123password321'
        HOME_NET='192.168.0.0/16'
        INTERNAL_NET='10.1.0.0/24' #ONLY /24 PREFIX
        
        NODE_TYPE=1 #1 for single install, 2 for vrrp Master, 3 for vrrp Backup, 4 for LoadBalancer
        
        ##### HA VARS ##### #Dont set "HA VARS" if $NODE_TYPE=1
        KEEPALIVED_VIP=192.168.1.254 #HA ip
        KEEPALIVED_PASSWORD=123changeme321 #Password for link Backup nodes
        KEEPALIVED_PRIORITY=150 #Recomendation: For master and LB set 150, for first Backup - 100. every next server one type should be lover than the previous
        
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


Если собирать "кластер" с нодой в режиме 4, то количество "воркеров" может быть любым (как минимум 9 должно поддерживаться без вмешательства в сам скрипт).


Нода установленная в 4 режиме будет балансировать трафик в соответствии с weight каждого воркера, поэтому важно правильно указать скорость каждого в переменой SERVERS_SOCK.

Для теста скорости можно использовать утилиту speedtest-cli

    apt-get update && apt-get install speedtest-cli
    speedtest-cli --source 10.1.0.1 #Если INTERNAL_NET=10.1.0.0/24, ip для интерфейса всегда берется первый из указанной сети.

Рекомендую несколько раз провести тест и вычислить некую среднюю скорость канала прокси.


Для уверенности и лучшей скорости в случае отказа нужно задавать KEEPALIVED_PRIORITY. На Master ноде рекомендую указывать на 50 больше чем на Backup(воркерах). А на каждом воркере на 10 меньше чем на предыдущем (Воркер с большим каналом прокси должен быть с самым большим приоритетом среди остальных).

Например: Master: 200, backup1: 150, backup2: 140.


При желании "воркеров" можно упаковать в контейнер с пробросанным 3228 портом и запускать на ноже с любой ОС. Но придется использовать network=host и режим privileged. 


Для установки в 1 режиме можно использовать Dockerfile и сам скрипт из https://github.com/govorunov-av/SquidFW/tree/main/docker . Но vrrp там нет.


Links:

    https://habr.com/ru/articles/267851/
    https://habr.com/ru/articles/272733/
