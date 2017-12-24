---
layout: blog
title: Load balancing with multiple public IPs using Nginx
topic: Load Balancers
type: Tutorials
categories: tutorials load-balancer nginx
date: 2017-12-23 21:30:00
banner: balancer.jpg
---
The link on which our websites are hosted has a very limited bandwidth (but never goes down). We host a lot of research papers, project videos and a lot of datasets on our websites that are delivered through this high availability link. But serving such heavy content on a limited bandwidth link will lead to horrible browsing experiences and eventually a downtime. The good thing is, we also have a high bandwidth link (but not reliable :disappointed:). I was asked to setup a reverse proxy on this link to deliver heavy content so that all our hosted websites can live happily.

## Assumptions
We'll need two reverse proxy servers, one on each public IP. Let's call the one on highly available limited bandwidth link `proxypass.iiit.ac.in` and the one on high bandwidth link `cdn.iiit.ac.in`. I'll be using domain names in this post since I have an intranet name server. You might want to replace these domain names with intranet IPs if you don't have one (Though I recommend that you set up one if have more than a few domains to manage. It'll be fun!). `proxypass.iiit.ac.in` will give a permanant redirect for some resources (based on file types like pdf, tar, zip, etc.,) to `cdn.iiit.ac.in` where the content would be served at better speed without effecting the user experience for browsing.

## Setting up proxypass.iiit.ac.in
### Installing Nginx
On CentOS 7, add the CentOS EPEL repository and then install Nginx.
{% highlight shell %}
sudo yum install epel-release
sudo yum install nginx
{% endhighlight %}

If using Ubuntu 16.04,
{% highlight shell %}
sudo apt update && sudo apt install nginx
{% endhighlight %}

Start Nginx server.
{% highlight shell %}
sudo systemctl start nginx
{% endhighlight %}

Enable Nginx to start on boot.
{% highlight shell %}
sudo systemctl enable nginx
{% endhighlight %}

### Building Nginx config
Nginx's `proxy_pass` module makes it behave like a reverse proxy <a href="http://nginx.org/en/docs/http/ngx_http_proxy_module.html" target="_blank">[refer]</a>. We'll setup all our domains as virtual hosts and use `proxy_pass` to fetch content from the actual servers on intranet. To automate things further, we can query an AXFR record from our public nameserver for the entire zone and build Nginx config based on it. In my case, most of the domains are on `.iiit.ac.in`. So, I can simply query for AXFR of `iiit.ac.in` and add rest of the domains manually (or do this for multiple domains if need be). We'll place all our virtual host configurations in `/etc/nginx/conf.d/` directory.

Before going to virtual hosts part, let us set up few things in `/etc/nginx/nginx.conf`. All the code samples below should go inside the `http {}` block of Nginx configuration. First, let's change the logging format as needed.
{% highlight nginx %}
log_format main '$remote_addr - $remote_user [$time_local] '
                '"$request" $status $body_bytes_sent '
                '"$http_referer" "$http_user_agent" '
                '"$http_x_forwarded_for"';
{% endhighlight %}

Now, let's increase the timeout for proxied connections.
{% highlight nginx %}
proxy_connect_timeout 300;
proxy_send_timeout    300;
proxy_read_timeout    300;
send_timeout          300;
{% endhighlight %}
This will set all the timeouts to 5 minutes.

Depending on the number of domains you want to proxy, you might want to increase `types_hash_max_size` and `server_names_hash_max_size` also.

Since we are using two reverse proxy servers to serve the same set of websites, there will be two points of entry for all these websites. In order to log everything at one place, we'll use `cdn.iiit.ac.in` as a reverse proxy for `proxypass.iiit.ac.in`. For this to work, we need to redirect clients not only based on file types but also based on source IP. That is, we want to return a redirect to `cdn.iiit.ac.in` only if the source IP is a non intranet IP (otherwise, there will be a redirection loop between `proxypass.iiit.ac.in` and `cdn.iiit.ac.in`). For this we'll use the `geo` module of Nginx.
{% highlight nginx %}
geo $external_ip {
    default         1;
    10.0.0.0/8      0; # You might want to replace this with your intranet subnet
}
{% endhighlight %}

Finally, include the configuration of all virtual hosts and add a default server for fallback in the same file.
{% highlight nginx %}
include /etc/nginx/conf.d/*.conf;

server {
    listen       80 default_server;
    listen       [::]:80 default_server;
    server_name  _;
    root         /usr/share/nginx/html;

    # Load configuration files for the default server block.
    include /etc/nginx/default.d/*.conf;

    location / {
        deny all;
    }

    error_page 404 /404.html;
        location = /40x.html {
    }

    error_page 500 502 503 504 /50x.html;
        location = /50x.html {
    }
}
{% endhighlight %}

Now, let us write the config for some random domain, say `dummy.iiit.ac.in`. We'll store the access log for each virtual host in a separate file and also maintain separate log files for SSL connections.
{% highlight nginx %}
server {
    listen 80;
    listen [::]:80;

    # Logging requests to file
    access_log  /var/log/nginx/dummy.iiit.ac.in.log  main;

    server_name dummy.iiit.ac.in;

    # These headers are required for redirection and 
    # reverse proxy to work to function properly
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Scheme $scheme;
    proxy_set_header Host $http_host;

    # Redirect to cdn.iiit.ac.in if source is not from intranet
    # Else, serve as a reverse proxy for requests from intranet IPs
    location ~* \.(zip|gz|tar|bz|rar|7z|xz|pdf|mp4|avi|mov|webm|wmv)$ {
        if ($external_ip) {
            return 301 http://cdn.iiit.ac.in/cdn/dummy.iiit.ac.in$request_uri;
        }
        proxy_pass http://dummy.iiit.ac.in;
    }

    location / {
        proxy_pass http://dummy.iiit.ac.in;
    }
}

# Simialrly for SSL connections. You can club both of these
# configurations if you don't have any special purpose of having
# two separate server blocks for SSL and non SSL connections.
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    # Setting SSL certificate and other options
    ssl_certificate /etc/pki/tls/private/iiit.ac.in.pem;
    ssl_certificate_key /etc/pki/tls/private/iiit.ac.in.pem;
    ssl_session_cache shared:SSL:1m;
    ssl_session_timeout  10m;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    access_log  /var/log/nginx/dummy.iiit.ac.in_ssl.log  main;

    server_name dummy.iiit.ac.in;

    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Scheme $scheme;
    proxy_set_header Host $http_host;

    location ~* \.(zip|gz|tar|bz|rar|7z|xz|pdf|mp4|avi|mov|webm|wmv)$ {
        if ($external_ip) {
            return 301 https://cdn.iiit.ac.in/cdn/dummy.iiit.ac.in$request_uri;
        }
        proxy_pass https://dummy.iiit.ac.in;
    }

    location / {
        proxy_pass https://dummy.iiit.ac.in;
    }
}
{% endhighlight %}

### Auto generation of Nginx config
It is possible to automate config generation by fetching the AFXR record and process the configuration required for all the domains. This can be done using a simple bash script. We'll put this bash script in `crontab` so that it fetches the record for some interval of time. I run this script for every 30 minutes. So, to add a new domain to our reverse proxy server, we just need to add an entry in the public name server and intranet name server and everything else will be done behind the scenes. Note that it is important to add a DNS entry in local name server too because our reverse proxy server queries the local IP of the domains from local name server. The automation script can be found here <a href="https://gist.github.com/jyotishp/4e1c9fae146e04a1361ab22e72e9572d#file-proxypass_config-sh" target="_blank">[proxypass_config.sh]</a>.

## Setting up cdn.iiit.ac.in
Again, first install Nginx, enable at boot and start it. Now, change the logging format also as required.

The Nginx configuration for CDN is fairly straight forward. We'll need only single (or two if looking for separate SSL one) server block. Before we proceed, let's revise what we want to do. We have some files that we want our CDN to serve. For example, if the client requests for 
{% highlight html %}
http://dummy.iiit.ac.in/some_path/some_big_file.zip
{% endhighlight %}
it gets `301` redirect to 
{% highlight html %}
http://cdn.iiit.ac.in/cdn/dummy.iiit.ac.in/some_path/some_big_file.zip
{% endhighlight %}
Our CDN has to strip `/cdn/` and `dummy.iiit.ac.in` parts of the request URI and pass rest of the request URI to `dummy.iiit.ac.in`. The configuration below has to go inside the `http {}` block of Nginx configuration.
{% highlight nginx %}
server {
    listen       80 default_server;
    listen       [::]:80 default_server;
    server_name  _;
    root         /usr/share/nginx/html;

    location / {
        set $iiit_host "";
        set $iiit_path $request_uri;
        if ($request_uri ~ ^/cdn/([^/]+)(/.*)$ ) {
            set $iiit_host $1;
            set $iiit_path $2;
            rewrite ^/cdn/([^/]+)(/.*)$ $2 break;
        }
        proxy_set_header Host $iiit_host;
        proxy_redirect off;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass http://proxypass.iiit.ac.in;
    }
}

# Simialrly for SSL connections. You can club both of these
# configurations if you don't have any special purpose of having
# two separate server blocks for SSL and non SSL connections.
server {
    listen       443 ssl http2 default_server;
    listen       [::]:443 ssl http2 default_server;
    server_name  _;
    root         /usr/share/nginx/html;

    ssl_certificate "/etc/pki/tls/certs/iiit.ac.in.crt";
    ssl_certificate_key "/etc/pki/tls/private/iiit.ac.in.key";
    ssl_session_cache shared:SSL:1m;
    ssl_session_timeout  10m;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        set $iiit_host "";
        set $iiit_path $request_uri;
        if ($request_uri ~ ^/cdn/([^/]+)(/.*)$ ) {
          set $iiit_host $1;
          set $iiit_path $2;
          rewrite ^/cdn/([^/]+)(/.*)$ $2 break;
        }
        proxy_set_header Host $iiit_host;
        proxy_redirect off;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass https://proxypass.iiit.ac.in;
    }

    error_page 404 /404.html;
        location = /40x.html {
    }

    error_page 500 502 503 504 /50x.html;
        location = /50x.html {
    }
}
{% endhighlight %}

Rewriting the request URI is absolutely necessary (you can skip the `$iiit_path`). If you don't rewrite and simply pass `$iiit_path` to the `proxy_pass`, Nginx would encode your request in a weird way (because it's the way things are implemented). For example, if you have `%20` in the URL, they get converted to whitespaces when they are given to `proxy_pass`. This will result in a `404` though the resource you are trying to fetch exists.

>A quote from documentation:
- If `proxy_pass` is specified **with URI**, when passing a request to the server, part of a **normalized** request URI matching the location is replaced by a URI specified in the directive
- If `proxy_pass` is specified **without URI**, a request URI is passed to the server in the same form as sent by a client when processing an original request

## Final Words
Before deploying make a thorough test if all domains are up and running. Check how Nginx is behaving when there are huge files queued for download. And also make sure that the URLs with special HTML characters are working as desired. Happy deploying!