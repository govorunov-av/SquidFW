# SquidFW
**Прозрачный прокси-кластер на базе Squid с поддержкой HTTPS-intercept, балансировкой по доменам и высокой доступностью**

SquidFW — это комплексное решение для автоматической развёртки и управления кластером прозрачных прокси-серверов на базе Squid. Проект позволяет:

- перехватывать и обрабатывать HTTPS-трафик (SSL Bump)
- интеллектуально распределять трафик по доменам: часть доменов через прокси (Redsocks), остальное — напрямую через шлюз по умолчанию
- организовывать отказоустойчивый кластер с использованием VRRP (Keepalived)
- автоматически балансировать нагрузку между воркерами по реальной скорости канала
- централизованно собирать логи, мониторить состояние и производительность
- интегрировать сетевой антивирус (ClamAV + ICAP)
- применять техники маскировки трафика (maybenot)

Проект ориентирован на ALT Linux p11 (p10 — поддерживается в legacy-режиме).

## Идеальная тополгогия

<img width="904" height="1022" alt="image" src="https://github.com/user-attachments/assets/e1af8d9b-90ed-4d6f-adbf-38c527992916" />


## Основные возможности

- Полноценный HTTPS-intercept. Установка корневых сертификатов не требуется!
- Высокая доступность и отказоустойчивость через VRRP
- Автоматический расчёт весов прокси-каналов через `speedtest-cli` (или ручная установка)
- Динамическая балансировка с хранением весов и приоритетов в Consul
- Централизованный мониторинг (Netdata streaming + Consul UI)
- Централизованный сбор логов (rsyslog с возможностью передачи на удалённый сервер)
- Сетевой антивирус через ICAP (ClamAV)
- Маскировка трафика с помощью maybenot (обфускация трафика)
- Поддержка запуска в Docker (NODE_TYPE=1)
- Автоматизация деплоя через GitLab CI/CD (по тегам и веткам)

## Сравнение режимов установки (NODE_TYPE)

| NODE_TYPE | Название | Основные компоненты | Сценарий |
|----------|----------|--------------------|----------|
| 1 | Простой узел | Squid + Redsocks | 1 нода, без отказоустойчивости |
| 2 | Мастер VRRP | Squid + Redsocks + Keepalived + Consul master | Главная нода, HA с Backup |
| 3 | Воркер / Backup VRRP | Squid + Redsocks + Keepalived | Строит масштабируемый кластер |
| 4 | Балансировщик нагрузки | Squid (cache_peer) + Consul master | Балансировка на воркеры |
| 5 | Сетевой антивирус | ClamAV + c-icap + Squid ICAP | Узел проверки трафика |
| 6 | Maybenot | Maybenot | Обфускация трафика |

## Системные требования

**ОС:** ALT Linux p11 (рекомендуется) / p10 (legacy)  
**Архитектура:** x86_64  
**Минимально:** 1 CPU, 1024 MB RAM на ноду (до 50 Мбит/с)  
**Сеть:** INTERNAL_NET `/24`, одно L2  
**Доступ в интернет**

## Быстрый старт

### Клонирование репозитория

```
git clone https://github.com/govorunov-av/SquidFW.git
cd SquidFW
```

2. Редактирования файла с переменными. Подробнее - далее

```
vim env.conf
```

3. Запуск установки

```
bash install.sh

bash install.sh maybenot #Если от скрипта необходима только одна функция - ее можно указать как $1, тогда выполниться только она
```

## Структура переменных в env.conf (группировка по типу ноды)

Стандартыне переменные, необходимые (кроме переменных мониторинга) для всех:

```
HOME_NET='192.168.0.0/16'
INTERNAL_NET='10.0.0.0/24' #ONLY /24 PREFIX

#Тип установки
NODE_TYPE= #1 for single install, 2 for vrrp Master, 3 for vrrp Backup, 4 for LoadBalancer, 5 for ClamAv network antivirus, 6 for install maybenot

#Пакеты
SQUID_LINK='https://github.com/govorunov-av/SquidFW/raw/refs/heads/main/packages/squid-7.3-alt1.x86_64.rpm'
SQUID_HELPER_LINK='https://github.com/govorunov-av/SquidFW/raw/refs/heads/main/packages/squid-helpers-7.3-alt1.x86_64.rpm'

#Мониторинг
RSYSLOG_INSTALL=0 #Set 1 or 0
RSYSLOG_COMMAND=''
SQUIDANALYZER=0 #Install darold/squidanalyzer on node (if rsyslog_install=1)
NETDATA_INSTALL=0 #Install netdata child with streaming on parent
NETDATA_DEST=''
NETDATA_API=''
```

### NODE_TYPE 1:
В данном режиме поддерживается только 1 нода. Все конфиги настраиваются в cli машины. На клиенте необходимо ее указать как шлюз.

```
INTERNAL_NET='10.10.10.0/24' #ONLY /24 PREFIX

PROXY_IP=
PROXY_PORT=
PROXY_LOGIN=
PROXY_PASSWORD=
RU_SITES="
.vk.com
"
PROXY_SITES="
.com
"
```

### NODE_TYPE 2:
В данном режиме устанавливается main нода кластера. Поддерживается любое* кол-во нод, но никакой балансировки не будет. Нода 2 типа будет главной, а присоединенная нода 3 типа будет бэкапом. На клиенте в качестве шлюза по умолчанию необходимо установить значение переменной $KEEPALIVED_VIP.

Переменные, для типа установки 2:

```
INTERNAL_NET='10.10.10.0/24' #ONLY /24 PREFIX

PROXY_IP=
PROXY_PORT=
PROXY_LOGIN=
PROXY_PASSWORD=
RU_SITES="
.vk.com
"
PROXY_SITES="
.com
"

KEEPALIVED_VIP= #vip - gateway for clients
KEEPALIVED_PASSWORD= #Password for link Backup nodes. Up to 8 symbols
```

### NODE_TYPE 3:
Данный режим является основным "воркером", конектится к 2 или 4 типам нод, устанавливается после них. При установки первого "воркера" нужно указать переменные RU_SITES и PROXY_SITES, при установке последующих - не нужно (просто оставлять их пустыми), далее этими конфигурациями можно управлять в consul.

Переменные, для типа установки 3:

```
INTERNAL_NET='10.10.10.0/24' #ONLY /24 PREFIX

PROXY_IP=
PROXY_PORT=
PROXY_LOGIN=
PROXY_PASSWORD=
RU_SITES="
.vk.com
"
PROXY_SITES="
.com
"

NEW_GATEWAY= #Change gateway to specified

KEEPALIVED_VIP= #vip - gateway for clients
KEEPALIVED_PASSWORD= #Password for link Backup nodes. Up to 8 symbols

#SET PROXY_WEIGHT or SPEEDTEST_INSTALL. Not and!
PROXY_WEIGHT=10 #Ex use proxy speed (Mbit/s)
SPEEDTEST_INSTALL=0 #1 or 0. You need access to speedtest site

#SET LB_SERVER and CONSUL_ENCRYPT FOR 3 NODE TYPE, if need to connect to node 4/2 type
LB_SERVER= #Ip of node with type 3
CONSUL_ENCRYPT='' #Consul encrypt from node 4/2 type, printed after install
```

### NODE_TYPE 4:

Данный режим устанавливает squid в режиме балансировки на squid_peer, используя weight (для равномерного распределения нагрузки, учитывая канал прокси). На клиенте указывается vrrp ip.

```
KEEPALIVED_VIP= #HA ip
KEEPALIVED_PASSWORD=password #Password for link Backup nodes
```

В конце установки будет выведен consul encrypt ключ, необходимый для подключений остальных нод в consul. 
Балансировка не является лучшим решением для балансировки шлюзов. Поэтому я написал небольшой скриптик, что более эффективно выполняет балансировку. Данный скрипт располагается по адресу https://github.com/govorunov-av/BashLb
Что бы воспользоваться им вместо squid с cache_peer нужно:
  - Первоначально сконфигурировать ВМ с помощью этого скрипта для NODE_TYPE=4
  - Выполнить следующие команды, для отключения squid и некоторых iptables правил
    
    ```
    systemctl disable --now custom-network.service
    iptables -t nat -F 
    git clone https://github.com/govorunov-av/BashLb.git
    cd BashLb/
    vim env.conf
    #Отредактировать файл переменных в соответствии с README
    bash install.sh "$(pwd)/script.sh"
    systemctl status BashLb
    ```


### NODE_TYPE 5:

Используется для установки clamav в режиме сетевого антивируса, с использованием icap и squid. Если предполагается его использование в прокси-кластере, то необхзодимо указать следующие переменные:

```
NEW_GATEWAY=
LB_SERVER=
CONSUL_ENCRYPT=''
```

На клиенте устанавливается сертификат CA (выводится после установки) и ip адрес данной ноды.

### NODE_TYPE 6:

Устанавливается только maybenot-tunnel (из моего репо)

```
MAX_FRAGMENT_SIZE=1400
MIX_FRAGMENT_SIZE=200
MAX_PADDING_SIZE=256
IDLE_THRESHOULD_MS=400
DUMMY_TRAFFIC_INTERVAL_MS=2000
```


## Типичные сценарии использования

Простой прозрачный прокси → NODE_TYPE=1\
Отказоустойчивый кластер 2 ноды → 1× NODE_TYPE=2 + 1× NODE_TYPE=3\
Масштабируемый кластер 3–? ноды → 1× NODE_TYPE=4 + много NODE_TYPE=3\
Проверка на вирусы всего трафика → NODE_TYPE=5 в цепочке с чем-либо\
Обфускация трафика прокси → NODE_TYPE=6 , gateway для воркеров\

## Мониторинг и логирование

Consul UI: http://<LB_SERVER>:8500\
Netdata (стриминг): порт 19999 на каждой ноде или main ноде к которой происходит стрим\
Логи Squid: /var/log/squid/access.log, cache.log\
Состояние redsocks: systemctl status redsocks, либо же в consul ui\
Проверка весов в Consul: "consul kv get -recurse squid/clients/" , либо в web\

## Архитектура

Все используемые скрипты находятся в папке /scripts, используемые кастомные сервисы в /etc/systemd/system/\
Основным сервисом является custom-network. Он пораждает много других сервисов, а так же управляет iptables\

## Ограничения и важные замечания

INTERNAL_NET обязательно должна быть подсеть /24\
speedtest-cli может не работать за некоторыми корпоративными прокси\
Maybenot увеличивает задержку и расход трафика\
Docker-режим поддерживает только NODE_TYPE=1 (без Keepalived)\

## Полезные ссылки

- [Intercept HTTPS с помощью Squid (Habr)](https://habr.com/ru/articles/267851/)\
- [Балансировка и фильтрация трафика (Habr)](https://habr.com/ru/articles/272733/)\
- [Streaming and replication reference](https://staging1--netdata-docusaurus.netlify.app/docs/streaming/streaming-configuration-reference)\
- [SquidAnalyzer](https://github.com/darold/squidanalyzer/tree/master)\
	


## Лицензия

GNU GPL v3.0\
© 2023–2026 govorunov-av\
