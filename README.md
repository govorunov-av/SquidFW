# SquidFW: Автоматическая установка и настройка прокси-кластера

Этот скрипт позволяет развернуть и настроить кластер прокси-серверов на базе **Squid**, с поддержкой **HTTPS Intercept**, балансировки трафика по доменам, отказоустойчивости и централизованного мониторинга.

---

## 📚 Оглавление

- ✨ Возможности
    
- 📈 Варианты установки (`NODE_TYPE`)
    
- 📅 Системные требования
    
- 🔧 Начальная настройка переменных
    
- ⚖️ Балансировка трафика (режим 4)
    
- 📊 Мониторинг и логирование
    
- 🚀 Docker
    
- 🔗 Полезные материалы
    
- 🌐 Эталонная топология

- 🛠️ Gitlab ci


---

## ✨ Возможности

- Поддержка HTTPS (Intercept)
    
- Перенаправление трафика по доменам: через прокси или напрямую
    
- Кластеризация с использованием Keepalived (VRRP)
    
- Автоматическая балансировка нагрузки по скорости канала
    
- Централизованный сбор логов (rsyslog)
    
- Мониторинг доступности и управление через Consul
	
- Мониторинг с помощью netdata (В режиме stream)
	
- Интеграция с сетевым антивирусом ClamAV (через ICAP)
    

---

## 📈 Варианты установки (`NODE_TYPE`)

|NODE_TYPE|Назначение|Компоненты|
|---|---|---|
|1|Простая установка|Squid + Redsocks|
|2|Master-нода с VRRP|Squid + Redsocks + Keepalived|
|3|Backup-нода VRRP|Squid + Redsocks + Keepalived|
|4|Балансировщик нагрузки|Squid с cache_peer|
|5|Сетевой антивирус|ClamAV + ICAP|

---

## 📅 Системные требования

- **ALT Linux P10** (можно использовать ALT JEOS P10)
    
- Скрипт требует пересборки Squid с патчами
    
- Используются мои `.rpm` пакеты по умолчанию
    

Если нужно использовать собственные пакеты, то можно пересобрать стандартные пакеты squid и squid_helpers в соответствии с данной [статьей](https://habr.com/ru/articles/267851/). После укажите ссылки в переменных:

```
SQUID_LINK="<ссылка на squid rpm>"
SQUID_HELPER_LINK="<ссылка на helpers rpm>"
```

---

## 🔧 Начальная настройка переменных

Перед запуском скрипта отредактируйте .env файл, в соответствии с типом установки(NODE_TYPE):

Стандартыне переменные, необходимые (кроме переменных мониторинга) для всех:

```
HOME_NET='192.168.0.0/16'
NODE_TYPE= #1 for single install, 2 for vrrp Master, 3 for vrrp Backup, 4 for LoadBalancer, 5 for ClamAv network antivirus

# Пакеты
SQUID_LINK='https://.../squid.rpm'
SQUID_HELPER_LINK='https://.../squid-helpers.rpm'

# Мониторинг
RSYSLOG_INSTALL=0 #Set 1 or 0
RSYSLOG_COMMAND=''
SQUIDANALYZER=0 #Install darold/squidanalyzer on node (if rsyslog_install=1)
NETDATA_INSTALL=0 #Install netdata child with streaming on parent
NETDATA_DEST=''
NETDATA_API=''
```

### 🔹 NODE_TYPE 1:
В данном режиме поддерживается только 1 нода. Все конфиги настраиваются в cli машины. На клиенте необходимо ее указать как шлюз.

Переменные, для типа установки 1:

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

### 🔹 NODE_TYPE 2:
В данном режиме устанавливается main нода кластера. Поддерживается любое* кол-во нод, но никакой балансировки не будет. Нода 2 типа будет главной, а присоединенная нода 3 типа - будет бэкапом. НА клиенте в качестве шлюза по умолчанию необходимо установить vrrp ip.

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

KEEPALIVED_VIP= #HA ip
```

### 🔹 NODE_TYPE 3:
Данный режим является основным "воркером", конектится к 2 или 4 типам нод, устанавливается после них. При установки первого "воркера" нужно указать переменные RU_SITES и PROXY_SITES, при установке последующих - не нужно (просто оставлять их пустыми). Далее конфигурациями можно управлять в  consul.

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

KEEPALIVED_VIP= #HA ip
KEEPALIVED_PASSWORD=password #Password for link Backup nodes

#SET LB_SERVER and CONSUL_ENCRYPT FOR 3 NODE TYPE, if need to connect to node 4 type
LB_SERVER=
CONSUL_ENCRYPT=''
```

### 🔹 NODE_TYPE 4:
Данный режим устанавливает squid в режиме балансировки на squid_peer, используя weight (для равномерного распределения нагрузки, учитывая канал прокси). На клиенте указывается vrrp ip.

Переменные, для типа установки 4:

```
KEEPALIVED_VIP= #HA ip
KEEPALIVED_PASSWORD=password #Password for link Backup nodes
```
В конце установки будет выведен consul encrypt ключ, необходимый для подключений остальных нод в consul. 

### 🔹 NODE_TYPE 5:
Используется для установки clamav в режиме сетевого антивируса, с использованием icap и squid. Если предполагается его использование в прокси-кластере, то необхзодимо указать следующие переменные:

```
NEW_GATEWAY=
LB_SERVER=
CONSUL_ENCRYPT=''
```

На клиенте устанавливается сертификат CA (выводится после установки) и ip адрес данной ноды.

---

## ⚖️ Балансировка трафика (режим 4)

Нода типа 4 автоматически рассчитывает `weight` для каждого воркера через `speedtest-cli` и сохраняет его в Consul.

### ✍️ Ручная настройка:

```
consul kv put squid/clients/$NET_IP/weight 75
```

> В целом weight - любое числовое значение, но предполагается что это скорость канала прокси.


### 🔐 Настройка VRRP приоритетов:

```
consul kv put squid/clients/$NET_IP/priority 241
```

> Keepalived использует значения от 1 до 255

---

## 📊 Мониторинг и логирование

- Мониторинг состояния `redsocks` происходит через `curl --interface $INTERNAL_NET_IP` http://ifconfig.me. В случае если прокси не работает, то будет статус сервиса redsocks, на соответствующей ноде, в статусе failed.
    

### Веб-интерфейс Consul
  Вебка находится по адресу http://$LB_SERVER:8500
  Приверно вот так будут выглядеть сервисы:
  <img width="1480" height="539" alt="Pasted image 20250729175553" src="https://github.com/user-attachments/assets/9a72ad1d-9056-44d1-84ad-4d39dfaa6616" />

### 📄 Централизованный сбор логов:

```
RSYSLOG_INSTALL=1
RSYSLOG_COMMAND='*.* @@192.168.123.123'
```

Можно подключить **LogAnalyzer** к rsyslog-серверу, что бы просматривать логи в вебе:
<img width="1869" height="1299" alt="Pasted image 20250729175241" src="https://github.com/user-attachments/assets/241894dd-e846-431b-86cd-533e9cdb3da9" />


### ⏱️ Мониторинг в реальном времени с помощью netdata

```
NETDATA_INSTALL=1 #Install netdata child with streaming on parent
NETDATA_DEST='192.168.12.1'
NETDATA_API=''
```

С настройкой parent сервера netdata можно ознакомится по [ссылке](https://staging1--netdata-docusaurus.netlify.app/docs/streaming/streaming-configuration-reference). Для получения api ключа достаточно ввести команду:
`cat /opt/netdata/var/lib/netdata/netdata.api.key`

---

## 🚀 Docker

Можно запустить ноду типа 1 в контейнере. Требуется:

- `--network host`
    
- `--privileged`
    
- Проброс порта `-p 3228:3228`
    

Пример Dockerfile и скрипт: [SquidFW Docker](https://github.com/govorunov-av/SquidFW/tree/main/docker)

> ❌ Keepalived в Docker-режиме не поддерживается!

На клиенте указать ip ноды с docker в качестве шлюза.


---

## 🛠️ Gitlab ci

Для централизованного управления можно использовать gitlab ci.

Для начала необходимо добавить воркера, в режиме shell.
Присоединение воркера на altlinux выглядит следующим образом:

```
apt-get update
apt-get install git gitlab-runner -y 
userdel gitlab-runner 
rm -rf /var/lib/gitlab-runner/
useradd gitlab-runner 
echo 'gitlab-runner ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
usermod -aG wheel gitlab-runner 
gitlab-runner install --user=gitlab-runner --working-directory=/home/gitlab-runner
gitlab-runner start
gitlab-runner register
```
Далее как и обычно, при добавлении раннера добавляем тег, регистрируем раннера
`gitlab-runner register`

Клонируем репозиторий, или просто копируем файлы руками.
Для удобства - можно создать 1 репозиторий и несколько веток, по ветке для каждой ноды. 
Тег нужно добавить в файле .gitlab-ci.yml
```
default:
    tags: 
        - <tag>
```

Тем самым, при изменении в файлах ветки - изменения автоматически произойдут на ноде.
<img width="558" height="128" alt="Pasted image 20250729175129" src="https://github.com/user-attachments/assets/771a4865-c3b8-44f4-b432-f29490be508d" />


---

## 🔗 Полезные материалы

- [Intercept HTTPS с помощью Squid (Habr)](https://habr.com/ru/articles/267851/)
    
- [Балансировка и фильтрация трафика (Habr)](https://habr.com/ru/articles/272733/)
	
- [Streaming and replication reference](https://staging1--netdata-docusaurus.netlify.app/docs/streaming/streaming-configuration-reference)
	
-  [SquidAnalyzer](https://github.com/darold/squidanalyzer/tree/master)
	

---

## 🌐 Эталонная топология

До 10 воркеров работают "из коробки", больше — возможно потребуется ручная настройки VRRP приоритета.

Эталонная топология выглядит следующим образом:
<img width="1593" height="931" alt="Pasted image 20250729170519" src="https://github.com/user-attachments/assets/36cd2230-7eae-4a02-8c94-c8fd83d5e96d" />



---

> 💬 Если у вас есть предложения по улучшению скрипта или возникли проблемы — создайте issue в репозитории.

---

© 2023-2025 govorunov-av. Licensed under GNU GPL v3.0.
