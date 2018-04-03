unset http_proxy
unset https_proxy
curl -LO https://web.iiit.ac.in/~path.kolekar/a.zsh

# Enabling cluster services at boot
systemctl enable flanneld kubelet kube-proxy

# Update Kubernetes client variables
sed -i 's/KUBE_MASTER="--master=http:\/\/127.0.0.1:8080"/KUBE_MASTER="--master=http:\/\/10.4.24.19:8080"/g' /etc/kubernetes/config
sed -i 's/KUBELET_ADDRESS="--address=127.0.0.1"/KUBELET_ADDRESS="--address=0.0.0.0"/g' /etc/kubernetes/kubelet
sed -i 's/KUBELET_API_SERVER="--api-servers=http:\/\/127.0.0.1:8080"/KUBELET_API_SERVER="--api-servers=http:\/\/10.4.24.19:8080"/g' /etc/kubernetes/kubelet

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
export https_proxy=http://proxy.iiit.ac.in
curl -L https://jyotishp.ml/cdn/tmux.conf > .tmux.conf
echo ""
echo "After reboot run 'zsh ~/a.zsh'"
atomic host upgrade --reboot
