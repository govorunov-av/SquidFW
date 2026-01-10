# Пере-собранные пакеты, пригодные для использования.

Отличия от стандартных пакетов altlinux p11:

1) Для поддержки прозрачного прокси с ssl (Проблема в not match DNS)

В `RPM/SOURCE/squid-7.3/src/client_side_request.cc`

```
     http->request->recordLookup(dns);
 
-    if (ia != NULL && ia->count > 0) {
-        // Is the NAT destination IP in DNS?
-        for (int i = 0; i < ia->count; ++i) {
-            if (clientConn->local.matchIPAddr(ia->in_addrs[i]) == 0) {
-                debugs(85, 3, HERE << "validate IP " << clientConn->local << " possible from Host:");
-                http->request->flags.hostVerified = true;
-                http->doCallouts();
-                return;
-            }
-            debugs(85, 3, HERE << "validate IP " << clientConn->local << " non-match from Host: IP " << ia->in_addrs[i]);
-        }
-    }
-    debugs(85, 3, HERE << "FAIL: validate IP " << clientConn->local << " possible from Host:");
-    hostHeaderVerifyFailed("local IP", "any domain IP");
+  debugs(85, 3, "validate IP " << clientConn->local << " possible from Host:");
+  http->request->flags.hostVerified = true;
+  http->doCallouts();
+  return;
 }
 
 void
```

В 394 строке, того же файла, убран лигний `ia`: 

```
- ClientRequestContext::hostHeaderIpVerify(const ipcache_addrs* ia, const Dns::LookupDetails &dns)
+ ClientRequestContext::hostHeaderIpVerify(const ipcache_addrs*, const Dns::LookupDetails &dns)
```
2) Проблема при установке - не может найти /bin/wbinfo

Из `RPM/SPEC/squid.spec` убраны зависимоти от wbinfo, а так же поддержка авторизации через wbinfo_group (В следствии чего авторизация через winbind будет недоступна!)
