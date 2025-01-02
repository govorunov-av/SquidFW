# SquidFW
en: This is a transparent squid, with https support, balancing traffic across domains. He sends certain domains to redsocks, the rest to the default gateway.
The script will automatically install and configure everything. You only need to specify the variables.
You also need to specify the domains that will be redirected to the proxy. After the string 'cat << EOF > /etc/squid/vpn_sites', specify the domains, in squid format (~140 line)
The script was made for alt linux p10, but you can also redo it for other distributions. For squid to work properly, it needs to be rebuilt according to the links below, but you can also use my packages(RPM). By default, my packages are used (~ 94 and 95 lines).



ru: Это прозрачный squid, с поддержкой https, балансирующий трафик по доменам. Определенные домены он отправляет на redsocks, остальное на default gateway.
Скрипт автоматически всё установит и настроит. Нужно только указать переменные.
Так же нужно указать домены, которые будут перенаправляться на прокси. После строки 'cat << EOF > /etc/squid/vpn_sites' укажите домены, в формате squid (~140 строка)
Скрипт сделан под alt linux p10, но вы можете переделать и под другие дистрибутивы. Для правильной работы squid, его необходимо пересобрать в соответствии с ссылками ниже, Но вы так же можете использовать мои пакеты(RPM). По умолчанию используются мои пакеты (~ 94 и 95 строки).

Variables:

    PROXY_IP='' #ex: 193.123.123.123
    PROXY_PORT='' #ex: 1234
    PROXY_LOGIN='J'
    PROXY_PASSWORD=''
    HOME_NET='' #ex: 192.168.0.0/16
    INTERNAL_NET='' #ex: 10.1.0.0/24

Links:

    https://habr.com/ru/articles/267851/
    https://habr.com/ru/articles/272733/
