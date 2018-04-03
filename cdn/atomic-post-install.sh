# Docker proxy
mkdir /etc/systemd/system/docker.service.d/
cat >/etc/systemd/system/docker.service.d/proxy.conf << EOF
[Service]
Environment=HTTP_PROXY=http://proxy.iiit.ac.in:8080/,HTTPS_PROXY=http://proxy.iiit.ac.in:8080/,NO_PROXY="localhost, 127.0.0.1, iiit.ac.in, .iiit.ac.in, iiit.net, .iiit.net, 172.16.0.0/12, 192.168.0.0/16, 10.0.0.0/8"
EOF
systemctl daemon-reload
systemctl restart docker.service

# Atomic proxy
echo "proxy=http://proxy.iiit.ac.in:8080" >> /etc/ostree/remotes.d/centos-atomic-host.conf

# Proxy for Yum Repos
sed -i '/gpgcheck=1/a proxy=http:\/\/proxy.iiit.ac.in:8080' /etc/yum.repos.d/CentOS-Base.repo

# Install requried tools
atomic host install git vim tmux zsh
atomic host upgrade --reboot
