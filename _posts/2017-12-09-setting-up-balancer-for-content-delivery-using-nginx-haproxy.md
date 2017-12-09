---
layout: blog
title: Setting up balancer for content delivery using Nginx/HAproxy
topic: Load Balancers
type: Tutorials
categories: tutorials load-balancer CDN
date: 2017-12-09 18:00:00
banner: balancer.jpg
---
<!-- A load balancer acts as the “traffic cop” sitting in front of your servers and routing client requests across all servers capable of fulfilling those requests in a manner that maximizes speed and capacity utilization and ensures that no one server is overworked, which could degrade performance. If a single server goes down, the load balancer redirects traffic to the remaining online servers. When a new server is added to the server group, the load balancer automatically starts to send requests to it.

Let us not focus too much on the theoritical aspects. Although load balancers usually serve one domain with multiple backend servers, there are cases where on public IP is shared across multiple backed domains. -->

## Assumptions
In this tutorial, I'll be assuming that you have two public IPs, say `123.123.1.10` and `123.123.2.20`. One of this IP is available 100% of the time but has limited bandwidth, say `123.123.1.10`, and the other has some down time issues but has high bandwidth, say `123.123.2.20`. We have a bunch of websites that share the public IP `123.123.1.10`. In order to save some bandwidth we might want to serve some assets of these websites through the other IP `123.123.2.20`. We want to do this at a server level so that there is no need for the individual website admins or maitainers to alter their content delivery URLs. In this tutorial, I'll be referring to two hosts `site1.example.com` and `site2.example.com` on your intranet that you want to make public.

Proxypass can be implemented using HAproxy or Nginx. We prefer Nginx as it has more intuitive configuration (and saves a lot of pain as the configuration can be split into multiple files unlike HAproxy which doesn't support include directive).

## Setting up Proxypass server (Using HAproxy)
This will have your public IP that has 100% uptime, `123.123.1.10`.
Use the following configuration
{% highlight apache %}
/etc/haproxy/haproxy.cfg
________________________

global
    log         /dev/log local0
    log         /dev/log local1 notice
    stats       socket /var/run/haproxy-admin.sock mode 660 level admin
    stats       timeout 30s
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon
    ca-base /etc/ssl/certs
    crt-base /etc/ssl/private
    tune.ssl.default-dh-param 2048
    ssl-default-bind-ciphers ...
    ssl-default-bind-options no-sslv3 no-tls-tickets
    ssl-default-server-ciphers ...
    ssl-default-server-options no-sslv3 no-tls-tickets

defaults
    log                     global
    mode                    http
    option                  httplog
    option                  dontlognull
    option http-server-close
    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000

frontend http_frontend
    bind *:80
    mode http

    acl     datasets_url    path_end -i .zip .tar .xz .bz .gz .rar .bz2 .7z
    http-request redirect location https://cdn.example.com/static/%[req.hdr(host)]%[path] if datasets_url
    acl host_site1.example.com hdr(host) site1.example.com
    acl host_site2.example.com hdr(host) site2.example.com
    use_backend site1.example.com_http if host_site1.example.com
    use_backend site2.example.com_http if host_site2.example.com
    default_backend fallback_backend

frontend https_frontend
    bind *:443 ssl crt /etc/ssl/private/example.com.pem
    mode http
    option httplog
    log global

    acl     https_datasets_url    path_end -i .zip .tar .xz .bz .gz .rar .bz2 .7z
    http-request redirect location https://cdn.example.com/static/%[req.hdr(host)]%[path] if https_datasets_url
	acl host_site1.example.com hdr(host) site1.example.com
    acl host_site2.example.com hdr(host) site2.example.com
    use_backend site1.example.com_http if host_site1.example.com
    use_backend site2.example.com_http if host_site2.example.com
    default_backend fallback_backend

backend fallback_backend
    mode http
    server fallback_backend_01 127.0.0.1:8080 check

backend site1.example.com_http
    mode http
    server site1.example.com_01 site1_intranet1.example.com:80 check
    # Optional secondary fallback
    server site1.example.com_02 site1_intranet2.example.com:80 check

backend site2.example.com_http
    mode http
    server site2.example.com_01 site2_intranet1.example.com:80 check

backend site1.example.com_https
    mode http
    server site1.example.com_01 site1_intranet1.example.com:443 check ssl verify none

backend site2.example.com_https
    mode http
    server site2.example.com_01 site2_intranet1.example.com:443 check ssl verify none

{% endhighlight %}

## Setting up Proxypass server (Using Nginx)
Skip this step if you are using HAproxy. This will have your public IP that has 100% uptime, `123.123.1.10`.
{% highlight nginx %}
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 3000;
}

http {
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   90;
    proxy_connect_timeout 300;
    proxy_send_timeout    300;
    proxy_read_timeout    300;
    send_timeout          300;
    types_hash_max_size 2048;
    server_names_hash_max_size 8192;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    include /etc/nginx/conf.d/*.conf;
{% endhighlight %}

Now, we will specify the configuration required for our websites in `/etc/nginx/conf.d/` directory. Below is a template for reference.
{% highlight nginx %}
/etc/nginx/conf.d/site1.example.com
___________________________________

server {
        listen 80;
        listen [::]:80;

        server_name site1.example.com www.site1.example.com;

        # Redirection for static content
        # We'll serve this through CDN
        location ~* \.(zip|gz|tar|bz|rar|7z|xz)$ {
                return 301 https://cdn.example.com/static/site1.example.com$request_uri;
        }

        location / {
                proxy_pass http://site1.example.com/; # Or your intranet IP
        }
}

server {
        listen 443 ssl http2;
        listen [::]:443 ssl http2;

        ssl_certificate "/etc/pki/nginx/cert.crt";
        ssl_certificate_key "/etc/pki/nginx/private/cert.key";
        ssl_session_cache shared:SSL:1m;
        ssl_session_timeout  10m;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;

        server_name site1.example.com www.site1.example.com;

        # Redirection for static content
        # We'll serve this through CDN
        location ~* \.(zip|gz|tar|bz|rar|7z|xz)$ {
                return 301 https://cdn.example.com/static/site1.example.com$request_uri;
        }

        location / {
                proxy_pass https://site1.example.com/; # Or your intranet IP
        }
}
{% endhighlight %}
Use this template for rest of the domains you want to set.

## Setting up CDN server (Using Nginx)
This will have the public IP that has higher bandwidth, `123.123.2.20`.
You can use HAproxy even for this part. But I'll be sticking to Nginx for the following reasons
- At the time I'm writing this, the latest Centos release supports HAproxy 1.5 which doesn't give much freedom with regular expressions and variables (Though HAproxy 1.6+ supports what I exactly want, I want to avoid it untill it is updated through official repositories).
- HAproxy configuration is a pain to manage for large number of websites.

The following configuration points the CDN to fetch resources from the proxypass server we have set above. This will make sure that there is a sngle point entry for all the websites we handle (A friend of mine suggested this :satisfied: and it's a great idea).

{% highlight nginx %}
/etc/nginx/nginx.conf
_____________________

user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 2000;
}

http {
    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   90;
    proxy_connect_timeout 300;
    proxy_send_timeout    300;
    proxy_read_timeout    300;
    send_timeout          300;
    types_hash_max_size 2048;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;
    include /etc/nginx/conf.d/*.conf;

    server {
        listen       80 default_server;
        listen       [::]:80 default_server;
        server_name  _;
        root         /usr/share/nginx/html;
        return 301 https://$host$request_uri;
    }

# Settings for a TLS enabled server.
    server {
        listen       443 ssl http2 default_server;
        listen       [::]:443 ssl http2 default_server;
        server_name  _;
        root         /usr/share/nginx/html;

        ssl_certificate "/etc/pki/nginx/cert.crt";
        ssl_certificate_key "/etc/pki/nginx/private/cert.key";
        ssl_session_cache shared:SSL:1m;
        ssl_session_timeout  10m;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;

        location / {
            set $intranet_host "";
            set $intranet_path $request_uri;

            if ($request_uri ~ ^/static/([^/]+)/(.*)$ ) {
              set $intranet_host $1;
              set $intranet_path $2;
            }

            proxy_set_header Host $intranet_host;
            proxy_redirect off;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass https://proxypass.example.com/$intranet_path; # Or intranet IP
        }

        error_page 404 /404.html;
            location = /40x.html {
        }

        error_page 500 502 503 504 /50x.html;
            location = /50x.html {
        }
    }

}
{% endhighlight %}

## Conclusion
Your sites, `site1.example.com` and `site2.example.com`, will be served through the IP with maximum uptime (Proxypass server) and contents that are not too much important (some downloads or datasets) will be served on IP that has higher bandwidth (CDN server).