#!/bin/bash
# Kubernetes Binarization Installer v0.0.4
# Author matrix-ops zhangweilong Dolphin
set -x xtrace
_ps4=$PS4
export PS4='[Line:${LINENO}] '
set -e

if [ "$0" == '-bash' ]; then
    curPath=/root
else
    curPath=$(readlink -f "$(dirname "$0")")
fi
echo $curPath
MasterIP=(192.168.33.100 192.168.33.101 192.168.33.102)
k8sVIP=192.168.33.200
while getopts i OPT; do
    # i后面没有冒号表示这是个布尔值的选项，带了这个选项即为真
    case $OPT in
    i)
        echo -e "\033[32m========================================================================\033[0m"
        echo -e "\033[32mKubernetes Binarization Installer\033[0m"
        echo -e "\033[32m欢迎使用KBI(Kubernetes Binarization Installer)\033[0m"
        echo -e "\033[32m========================================================================\033[0m"
        echo -e "\033[32m请在部署节点执行安装操作，部署节点可以是集群节点中的其中一个,或是任何可以连接至目标K8s集群的节点\033[0m"
        echo -e "\033[32m如果是在云环境，请确保安全组放通VRRP协议（IP协议号112），在OpenStack中，还需要配置Master节点端口的allowed-port-pairs功能\033[0m"
        # read -p "输入Master节点IP,以空格分割:" -a MasterIP
        # read -p "输入Node节点IP,以空格分割,默认与Master节点相同:" -a NodeIP
        # read -p "输入K8s集群VIP:" k8sVIP
        read -p "输入Pod网段,以CIDR格式表示,默认172.23.0.0/16(按回车跳过):" podNet
        read -p "输入Service网段,以CIDR格式表示,默认10.253.0.0/16(按回车跳过):" serviceNet
        read -p "输入Kubernetes版本,默认1.18.10(按回车跳过): " k8sVersion
        read -p "输入docker-ce版本,默认最新版(按回车跳过): " dockerVersion
        ;;
    ?)
        echo -e "\033[31mMasterIP Is None\033[0m"
        exit 1
        ;;
    esac
done

# Master节点数量
mCount=${#MasterIP[@]}
if [ $mCount -eq 0 ]; then
    echo -e "\033[31mMasterIP Is None\033[0m"
fi
# Node节点数量
nCount=${#NodeIP[@]}
if [ $nCount -eq 0 ]; then
    nodeArray=(${MasterIP[@]})
    NodeIP=(${MasterIP[@]})
else
    nodeArray=(${MasterIP[@]} ${NodeIP[@]})
fi
echo "节点总数:${#nodeArray[@]},Master数量:${#MasterIP[@]},Node数量:${#NodeIP[@]}"
echo "Master节点："
for node in ${MasterIP[@]}; do echo $node; done
echo "Node节点:"
for node in ${NodeIP[@]}; do echo $node; done
echo
if [ -z "$k8sVersion" ]; then
    k8sVersion=v1.20.0
fi
if [ -z "$podNet" ]; then
    podNet=172.23.0.0/16
fi
if [ -z "$serviceNet" ]; then
    serviceNet=10.253.0.0/16
fi
firstServiceIP=$(echo $serviceNet | awk -F'/' '{print $1}' | sed 's/0$/1/')
clusterDnsIP=$(echo $serviceNet | awk -F'/' '{print $1}' | sed 's/0$/2/')

mkdir -p /etc/kubernetes/{cfg,bin,ssl}
if [[ -e /etc/kubernetes/cfg/token.csv ]]; then
    bootstrapToken=$(awk -F',' '{print $1}' /etc/kubernetes/cfg/token.csv)
else
    bootstrapToken=$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')
fi

autoSSHCopy() {
    echo -e "\033[32m正在配置各节点SSH互信免密登录..........\033[0m"
    if [ ! -e /root/.ssh/id_rsa ]; then
        echo "公钥文件不存在"
        ssh-keygen -t rsa -P '' -f /root/.ssh/id_rsa
    fi
    for node in ${nodeArray[@]}; do ssh-copy-id $node; done
    for node in ${nodeArray[@]}; do ssh $node 'mkdir -p /etc/kubernetes/{cfg,bin,ssl}'; done
}

# Preparation
preparation() {
    cd $curPath
    echo -e "\033[32m开始执行部署流程..........\033[0m"
    cat <<EOF >/etc/yum.repos.d/docker-ce.repo
#/etc/yum.repos.d/docker-ce.repo
[docker-ce-stable]
name=Docker CE Stable - \$basearch
baseurl=https://mirrors.aliyun.com/docker-ce/linux/centos/7/\$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/docker-ce/linux/centos/gpg
EOF

    cat <<EOF >/etc/kubernetes/cfg/kubernetes.conf
net.core.netdev_max_backlog=10000
net.core.somaxconn=32768
net.ipv4.tcp_max_syn_backlog=8096
fs.inotify.max_user_instances=8192
fs.file-max=2097152
fs.inotify.max_user_watches=524288
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 12582912 16777216
net.ipv4.tcp_wmem=4096 12582912 16777216
net.core.rps_sock_flow_entries=8192
net.ipv4.neigh.default.gc_thresh1=2048
net.ipv4.neigh.default.gc_thresh2=4096
net.ipv4.neigh.default.gc_thresh3=8192
vm.max_map_count=262144
kernel.threads-max=30058
net.ipv4.ip_forward=1
kernel.core_pattern=core
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
vm.swappiness=0
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_watches=89100
fs.file-max=52706963
fs.nr_open=52706963
net.ipv6.conf.all.disable_ipv6=1
EOF

    # 复制阿里云yum源配置文件和kubernetes.conf内核参数文件并安装依赖包
    mkdir -p $curPath/cfssl
    mkdir -p $curPath/yaml
    mkdir -p $curPath/images
    yum install wget -y &>/dev/null
    if [ -f "$curPath/cfssl/cfssl-certinfo_linux-amd64" ]; then
        echo -e "\033[32mcfssl-certinfo_linux-amd64 exist..........\033[0m"
    else
        wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64 -O $curPath/cfssl/cfssl-certinfo_linux-amd64
    fi

    if [ -f "$curPath/cfssl/cfssljson_linux-amd64" ]; then
        echo -e "\033[32mcfssljson_linux-amd64  exist..........\033[0m"
    else
        wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 -O $curPath/cfssl/cfssljson_linux-amd64
    fi
    if [ -f "$curPath/cfssl/cfssl_linux-amd64" ]; then
        echo -e "\033[32mcfssl_linux-amd64 exist..........\033[0m"
    else
        wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 -O $curPath/cfssl/cfssl_linux-amd64
    fi
    if [ -f "$curPath/yaml/calico.yaml" ]; then
        echo -e "\033[32mcalico.yaml exist..........\033[0m"
    else
        # wget https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
        wget https://docs.projectcalico.org/v3.15/manifests/calico.yaml -O $curPath/yaml/calico.yaml
        sed -i 's/docker.io\///g' $curPath/yaml/calico.yaml
        sed -i 's/v3.15.5/v3.15.1/g' $curPath/yaml/calico.yaml

    fi

    \cp $curPath/cfssl/cfssl-certinfo_linux-amd64 /usr/local/bin/cfssl-certinfo
    \cp $curPath/cfssl/cfssljson_linux-amd64 /usr/local/bin/cfssljson
    \cp $curPath/cfssl/cfssl_linux-amd64 /usr/local/bin/cfssl
    chmod a+x /usr/local/bin/cfssl*

    if [ ! -d /etc/kubernetes/ssl/ca ]; then mkdir -p /etc/kubernetes/ssl/ca; fi
    # 生成CA证书和私钥
    echo -e "\033[32m生成CA自签证书和私钥..........\033[0m"
    cat <<EOF >/etc/kubernetes/ssl/ca/ca-config.json
{
    "signing": {
        "default": {
            "expiry": "876000h"
        },
        "profiles": {
            "kubernetes": {
                "expiry": "876000h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            }
        }
    }
}
EOF
    # 签名请求（CSR）的 JSON 配置文件
    cat <<EOF >/etc/kubernetes/ssl/ca/ca-csr.json
{
    "CA": {
        "expiry": "876000h",
        "pathlen": 0
    },
    "CN": "kubernetes",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "ST": "GuangDong",
            "L": "GuangZhou",
            "O": "Dolphin",
            "OU": "Ops"
        }
    ]
}
EOF

    cd /etc/kubernetes/ssl/ca
    if [[ ! -e /etc/kubernetes/ssl/ca/ca.pem && ! -e /etc/kubernetes/ssl/ca/ca-key.pem ]]; then
        cfssl gencert -initca /etc/kubernetes/ssl/ca/ca-csr.json | cfssljson -bare ca
    fi

    for node in ${nodeArray[@]}; do
        scp /etc/yum.repos.d/docker-ce.repo root@$node:/etc/yum.repos.d/
        scp /etc/kubernetes/cfg/kubernetes.conf root@$node:/etc/kubernetes/cfg/

        ssh $node "yum install -y curl chrony sysstat conntrack ipvsadm ipset jq iptables psmisc iptables-services libseccomp && modprobe br_netfilter && sysctl -p /etc/kubernetes/cfg/kubernetes.conf && mkdir -p /etc/kubernetes/ssl/ca &> /dev/null"
        ssh $node "systemctl mask firewalld ; setenforce 0 ; sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config"
        ssh $node "modprobe br_netfilter ip_vs_rr nf_conntrack nf_conntrack_ipv4 &> /dev/null"
        if [ -z "$dockerVersion" ]; then
            ssh $node "yum install docker-ce -y"
        else
            ssh $node "yum install docker-ce-$dockerVersion -y"
        fi
        scp /etc/kubernetes/ssl/ca/* $node:/etc/kubernetes/ssl/ca
        echo -e "\033[32m节点$node 初始化安装完成\033[0m"
        echo -e "\033[32m====================\033[0m"
        echo
    done

    # iptables
    echo -e "\033[32m正在为各节点配置iptables规则..........\033[0m"
    cat <<EOF >/etc/sysconfig/iptables
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 443 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 514 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 1080 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 2379 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 2380 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 6443 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 8080 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 8443 -j ACCEPT
-A INPUT -m pkttype --pkt-type multicast -j ACCEPT
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
COMMIT
EOF
    for node in ${nodeArray[@]}; do
        scp /etc/sysconfig/iptables $node:/etc/sysconfig/iptables
        ssh $node "systemctl restart iptables"
    done

    # 配置NTP
    # 将以输入的第一个MasterIP作为NTP服务器
    echo -e "\033[32m正在配置NTP服务器，服务器地址为${MasterIP[0]}..........\033[0m"
    allowNTP=${MasterIP[0]}
    netNTP=$(echo $allowNTP | awk -F'.' '{print $1,$2 }' | sed 's/ /./')
    cat <<EOF >/tmp/chrony.conf
server ntp1.aliyun.com iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
allow ${netNTP}.0.0/16
logdir /var/log/chrony
EOF
    cat <<EOF >/tmp/chrony.conf_otherNode
server ${MasterIP[0]} iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
EOF
    scp /etc/chrony.conf ${MasterIP[0]}:/etc/
    ssh ${MasterIP[0]} "systemctl restart chronyd"
    echo -e "\033[32mNTP服务器完成..........\033[0m"
}

deployHaproxyKeepalived() {
    # 生成Haproxy的配置文件，默认使用MasterIP中的前三个节点

    for node in ${MasterIP[@]}; do ssh $node 'if id -u keepalived_script >/dev/null 2>&1; then echo "user keepalived_script exists"; else useradd keepalived_script; fi'; done
    for node in ${MasterIP[@]}; do ssh $node "echo 'keepalived_script ALL = (root) NOPASSWD:ALL' > /etc/sudoers.d/keepalived_script"; done
    cat <<EOF >/tmp/haproxy.cfg
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /var/run/haproxy-admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    nbproc 1

defaults
    log     global
    timeout connect 5000
    timeout client  10m
    timeout server  10m

listen  admin_stats
    bind 0.0.0.0:10080
    mode http
    log 127.0.0.1 local0 err
    stats refresh 30s
    stats uri /status
    stats realm welcome login\ Haproxy
    stats auth admin:DreamCatcher
    stats hide-version
    stats admin if TRUE

listen kube-master
    bind 0.0.0.0:8443
    mode tcp
    option tcplog
    balance source
    server k8s-master1 ${MasterIP[0]}:6443 check inter 2000 fall 2 rise 2 weight 1
    server k8s-master2 ${MasterIP[1]}:6443 check inter 2000 fall 2 rise 2 weight 1
    server k8s-master3 ${MasterIP[2]}:6443 check inter 2000 fall 2 rise 2 weight 1
EOF

    # 安装配置Keepalived和Haproxy，并根据节点的不同分别为不同节点的Keepalived设置优先级
    weight=1
    for node in ${MasterIP[@]}; do
        ((keepalivedPriority = $weight + 100))
        ssh $node "yum install haproxy keepalived -y && systemctl enable haproxy keepalived"
        interfaceName=$(ssh $node "ip a | grep -i $node -B 2 | awk 'NR==1{print \$2}' | sed 's/://'")
        cat <<EOF >/tmp/keepalived.conf
global_defs {
    router_id k8s-master-$node
}

vrrp_script check-haproxy {
    script "sudo killall -0 haproxy"
    interval 5
    weight -30
}

vrrp_instance VI-kube-master {
    state MASTER
    priority $keepalivedPriority
    dont_track_primary
    interface $interfaceName
    virtual_router_id 68
    advert_int 3
    track_script {
        check-haproxy
    }
    virtual_ipaddress {
        $k8sVIP
    }
}
EOF
        ((weight = $weight + 10))
        scp /tmp/haproxy.cfg $node:/etc/haproxy/haproxy.cfg
        scp /tmp/keepalived.conf $node:/etc/keepalived/
        echo -e "\033[32m节点$node 正在启动Haproxy && Keepalived..........\033[0m"
        ssh $node "systemctl start haproxy keepalived && systemctl enable haproxy keepalived"
        if [ $? ]; then
            echo -e "\033[32m节点${i} Haproxy && Keepalived启动完成\033[0m"
        else
            echo -e "\033[31m节点${i} Haproxy && Keepalived启动失败，请执行systemctl status keepalived haproxy查看日志\033[0m"
        fi
        echo
    done
}

deployETCD() {
    echo -e "\033[32m正在部署etcd..........\033[0m"
    if [ ! -d $curPath/software ]; then mkdir -p $curPath/software; fi
    if [ ! -d /etc/kubernetes/bin/etcd ]; then mkdir -p /etc/kubernetes/bin/etcd/; fi
    cat <<EOF >/etc/kubernetes/bin/etcd/etcd-csr.json
    {
        "CN": "etcd",
        "hosts": [
            "127.0.0.1",
            "${MasterIP[0]}",
            "${MasterIP[1]}",
            "${MasterIP[2]}"
        ],
        "key": {
            "algo": "rsa",
            "size": 2048
        },
        "names": [
            {
                "C": "CN",
                "ST": "GuangDong",
                "L": "GuangZhou",
                "O": "Dolphin",
                "OU": "Ops"
            }
        ]
    }
EOF

    cd /etc/kubernetes/bin/etcd/
    if [[ ! -e /etc/kubernetes/bin/etcd/etcd.pem && ! -e /etc/kubernetes/bin/etcd/etcd-key.pem ]]; then
        cfssl gencert -ca=/etc/kubernetes/ssl/ca/ca.pem \
            -ca-key=/etc/kubernetes/ssl/ca/ca-key.pem \
            -config=/etc/kubernetes/ssl/ca/ca-config.json \
            -profile=kubernetes etcd-csr.json | cfssljson -bare etcd
    fi
    # 生成etcd.pem etcd-key.pem
    if [[ ! -e /etc/kubernetes/bin/etcd/etcd.pem && ! -e /etc/kubernetes/bin/etcd/etcd-key.pem ]]; then
        cfssl gencert -ca=/etc/kubernetes/ssl/ca/ca.pem \
            -ca-key=/etc/kubernetes/ssl/ca/ca-key.pem \
            -config=/etc/kubernetes/ssl/ca/ca-config.json \
            -profile=kubernetes etcd-csr.json | cfssljson -bare etcd
    fi

    if [[ ! -e $curPath/software/etcd-v3.3.10-linux-amd64.tar.gz ]]; then
        wget https://github.com/etcd-io/etcd/releases/download/v3.3.10/etcd-v3.3.10-linux-amd64.tar.gz -O $curPath/software/etcd-v3.3.10-linux-amd64.tar.gz
        tar xvf $curPath/software/etcd-v3.3.10-linux-amd64.tar.gz -C /tmp
    fi

    index=0
    for node in ${MasterIP[@]}; do
        if [ ! -d /tmp/etcd/ ]; then ssh $node "mkdir /tmp/etcd/"; fi
        cat <<EOF >/tmp/etcd/etcd.conf
ETCD_ARGS="--name=etcd-$index \\
  --cert-file=/etc/kubernetes/bin/etcd/etcd.pem \\
  --key-file=/etc/kubernetes/bin/etcd/etcd-key.pem \\
  --peer-cert-file=/etc/kubernetes/bin/etcd/etcd.pem \\
  --peer-key-file=/etc/kubernetes/bin/etcd/etcd-key.pem \\
  --trusted-ca-file=/etc/kubernetes/ssl/ca/ca.pem \\
  --peer-trusted-ca-file=/etc/kubernetes/ssl/ca/ca.pem \\
  --initial-advertise-peer-urls=https://$node:2380 \\
  --listen-peer-urls=https://0.0.0.0:2380 \\
  --listen-client-urls=https://0.0.0.0:2379 \\
  --advertise-client-urls=https://$node:2379 \\
  --initial-cluster-token=etcd-cluster-1 \\
  --initial-cluster=etcd-0=https://${MasterIP[0]}:2380,etcd-1=https://${MasterIP[1]}:2380,etcd-2=https://${MasterIP[2]}:2380 \\
  --initial-cluster-state=new \\
  --data-dir=/var/lib/etcd"
EOF
        cat <<EOF >/tmp/etcd/etcd.service
[Unit]
Description=Etcd Server
Documentation=https://github.com/coreos
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
WorkingDirectory=/var/lib/etcd/
EnvironmentFile=/usr/local/etc/etcd.conf
ExecStart=/usr/local/bin/etcd \$ETCD_ARGS
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

        if $(ssh $node "[[ -f /etc/systemd/system/etcd.service ]]"); then
            echo -e "\033[32m节点$node 已存在ETCD systemd service文件，跳过此步骤..........\033[0m"
        else
            scp /tmp/etcd/etcd.service $node:/etc/systemd/system/ &>/dev/null &
        fi

        if $(ssh $node "systemctl status etcd &> /dev/null"); then
            echo -e "\033[32m节点$node ETCD正在运行中，跳过此步骤..........\033[0m"
        else
            scp /tmp/etcd-v3.3.10-linux-amd64/etcd* $node:/usr/local/bin
        fi

        if $(ssh $node "[[ -d /etc/kubernetes/bin/etcd/ ]]"); then
            echo -e "\033[32m节点$node 已存在/etc/kubernetes/bin/etcd/目录，跳过此步骤..........\033[0m"
        else
            ssh $node "mkdir -p /etc/kubernetes/bin/etcd/"
        fi

        if $(ssh $node "[[ -d /var/lib/etcd/ ]]"); then
            echo -e "\033[32m节点$node 已存在/var/lib/etcd/目录，跳过此步骤..........\033[0m"
        else
            ssh $node "mkdir -p /var/lib/etcd/"
        fi

        if $(ssh $node "[[ -d /var/lib/etcd/ ]]"); then
            echo -e "\033[32m节点$node 已存在/var/lib/etcd/目录，跳过此步骤..........\033[0m"
        else
            ssh $node "mkdir -p  /var/lib/etcd/"
        fi

        if $(ssh $node "[[ -f /etc/kubernetes/bin/etcd/etcd-key.pem ]]"); then
            echo -e "\033[32m节点$node 已存在ETCD证书私钥文件，跳过此步骤..........\033[0m"
        else
            scp /etc/kubernetes/bin/etcd/* $node:/etc/kubernetes/bin/etcd/
        fi

        scp /tmp/etcd/etcd.conf $node:/usr/local/etc/
        let index+=1
        echo
    done

    echo -e "\033[32m正在启动etcd.....\033[0m"
    ssh ${MasterIP[0]} "systemctl enable etcd && systemctl start etcd " &
    sleep 5

    for node in ${MasterIP[@]}; do
        if [ ! $node = ${MasterIP[0]} ]; then
            ssh $node "systemctl enable etcd && systemctl start etcd "
            if [ $? ]; then
                echo -e "\033[32m${node} etcd启动成功\033[0m"
            else
                echo -e "\033[31m${node} etcd启动失败，请检查日志\033[0m"
            fi
        fi
    done
}

setKubectl() {
    if [ -f "$curPath/software/kubernetes-server-linux-amd64.tar.gz" ]; then
        echo -e "\033[32mkubernetes-server-linux-amd64.tar.gz exist\033[0m"
    else
        # https://dl.k8s.io/v1.20.0/kubernetes-server-linux-amd64.tar.gz
        wget https://dl.k8s.io/${k8sVersion}/kubernetes-server-linux-amd64.tar.gz -O $curPath/software/kubernetes-server-linux-amd64.tar.gz
    fi

    tar xvf $curPath/software/kubernetes-server-linux-amd64.tar.gz -C /tmp/ && cd /tmp/kubernetes/server/bin && rm -rf *.tar *.docker_tag
    for node in ${nodeArray[@]}; do
        scp /tmp/kubernetes/server/bin/* $node:/usr/local/bin
        # apiextensions-apiserver kube-apiserver kube-proxy kubeadm kubelet kube-aggregator
        # kube-controller-manager kube-scheduler kubectl mounter
        ssh $node "chmod a+x /usr/local/bin/*"
    done

    if [ ! -d /etc/kubernetes/bin/admin ]; then mkdir -p /etc/kubernetes/bin/admin; fi
    cd /etc/kubernetes/bin/admin
    cat <<EOF >/etc/kubernetes/bin/admin/admin-csr.json
    {
        "CN": "admin",
        "hosts": [],
        "key": {
            "algo": "rsa",
            "size": 2048
        },
        "names": [
            {
                "C": "CN",
                "ST": "GuangZhou",
                "L": "GuangDong",
                "O": "system:masters",
                "OU": "Ops"
            }
        ]
    }
EOF

    if [[ ! -e /etc/kubernetes/bin/admin/admin.pem && ! -e /etc/kubernetes/bin/admin/admin-key.pem ]]; then
        cfssl gencert -ca=/etc/kubernetes/ssl/ca/ca.pem \
            -ca-key=/etc/kubernetes/ssl/ca/ca-key.pem \
            -config=/etc/kubernetes/ssl/ca/ca-config.json \
            -profile=kubernetes /etc/kubernetes/bin/admin/admin-csr.json | cfssljson -bare admin
    fi

    kubectl config set-cluster kubernetes \
        --certificate-authority=/etc/kubernetes/ssl/ca/ca.pem \
        --embed-certs=true \
        --server=https://${k8sVIP}:8443 \
        --kubeconfig=/etc/kubernetes/bin/admin/admin.conf

    kubectl config set-credentials admin \
        --client-certificate=/etc/kubernetes/bin/admin/admin.pem \
        --embed-certs=true \
        --client-key=/etc/kubernetes/bin/admin/admin-key.pem \
        --kubeconfig=/etc/kubernetes/bin/admin/admin.conf

    kubectl config set-context admin@kubernetes \
        --cluster=kubernetes \
        --user=admin \
        --kubeconfig=/etc/kubernetes/bin/admin/admin.conf

    kubectl config use-context admin@kubernetes --kubeconfig=/etc/kubernetes/bin/admin/admin.conf

    for node in ${MasterIP[@]}; do
        ssh $node "mkdir -p /etc/kubernetes/bin/admin /root/.kube/ &"
        scp /etc/kubernetes/bin/admin/admin* $node:/etc/kubernetes/bin/admin/ 2>/dev/null
        scp /etc/kubernetes/bin/admin/admin.conf $node:/root/.kube/config 2>/dev/null
        echo -e "\033[32m${node} kubectl配置完成\033[0m"
    done
}

# 网络插件,可是node 状态变为ready
deployFlannel() {
    mkdir -p /etc/kubernetes/bin/flannel/ 2>/dev/null
    cd /etc/kubernetes/bin/flannel/
    cat <<EOF >/etc/kubernetes/bin/flannel/flannel-csr.json
    {
        "CN": "flanneld",
        "hosts": [],
        "key": {
            "algo": "rsa",
            "size": 2048
        },
        "names": [
            {
                "C": "CN",
                "ST": "GuangDong",
                "L": "GuangZhou",
                "O": "Dolphin",
                "OU": "Ops"
            }
        ]
    }
EOF

    if [[ ! -e /etc/kubernetes/bin/flannel/flannel.pem && ! -e /etc/kubernetes/bin/flannel/flannel-key.pem ]]; then
        cfssl gencert -ca=/etc/kubernetes/ssl/ca/ca.pem \
            -ca-key=/etc/kubernetes/ssl/ca/ca-key.pem \
            -config=/etc/kubernetes/ssl/ca/ca-config.json \
            -profile=kubernetes /etc/kubernetes/bin/flannel/flannel-csr.json | cfssljson -bare flannel
    fi

    etcdctl --endpoints=https://${MasterIP[0]}:2379 \
        --ca-file=/etc/kubernetes/ssl/ca/ca.pem \
        --cert-file=/etc/kubernetes/bin/flannel/flannel.pem \
        --key-file=/etc/kubernetes/bin/flannel/flannel-key.pem \
        set /kubernetes/network/config '{"Network":"'${podNet}'", "SubnetLen": 24, "Backend": {"Type": "vxlan"}}'

    if [ ! -d $curPath/software/flanneld ]; then mkdir -p $curPath/software/flanneld; fi
    if [[ ! -e $curPath/software/flanneld/flanneld ]]; then
        wget https://github.com/flannel-io/flannel/releases/download/v0.14.0/flanneld-amd64 -O $curPath/software/flanneld/flanneld
    fi

    if [[ ! -e /usr/local/bin/flanneld ]]; then
        cp $curPath/software/flanneld/flanneld /usr/local/bin/
    fi
    if [[ ! -e $curPath/software/flanneld/mk-docker-opts.sh ]]; then
        wget https://raw.githubusercontent.com/flannel-io/flannel/master/dist/mk-docker-opts.sh -O $curPath/software/flanneld/mk-docker-opts.sh
    fi

    cp $curPath/software/flanneld/mk-docker-opts.sh /usr/local/bin/
    chmod a+x /usr/local/bin/*

    cat <<EOF >/etc/systemd/system/flanneld.service
[Unit]
Description=Flanneld overlay address etcd agent
Documentation=https://github.com/coreos
After=network.target
After=network-online.target
Wants=network-online.target
After=etcd.service
Before=docker.service

[Service]
Type=notify
EnvironmentFile=/usr/local/etc/flanneld.conf
ExecStart=/usr/local/bin/flanneld \$FLANNELD_ARGS
ExecStartPost=/usr/local/bin/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d /run/flannel/docker
Restart=on-failure

[Install]
WantedBy=multi-user.target
RequiredBy=docker.service
EOF

    cat <<EOF >/usr/local/etc/flanneld.conf
FLANNELD_ARGS="-etcd-cafile=/etc/kubernetes/ssl/ca/ca.pem \\
  -etcd-certfile=/etc/kubernetes/bin/flannel/flannel.pem \\
  -etcd-keyfile=/etc/kubernetes/bin/flannel/flannel-key.pem \\
  -etcd-endpoints=https://${MasterIP[0]}:2379,https://${MasterIP[1]}:2379,https://${MasterIP[2]}:2379 \\
  -etcd-prefix=/kubernetes/network"
EOF

    cat <<EOF >/tmp/docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
BindsTo=containerd.service
After=network-online.target firewalld.service containerd.service
Wants=network-online.target
Requires=docker.socket
[Service]
Type=notify
EnvironmentFile=-/run/flannel/docker
ExecStart=/usr/bin/dockerd -H fd:// \$DOCKER_NETWORK_OPTIONS --containerd=/run/containerd/containerd.sock
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process
[Install]
WantedBy=multi-user.target
EOF
    for node in ${nodeArray[@]}; do

        ssh $node "if [ ! -d /etc/kubernetes/bin/flannel/ ];then mkdir -p /etc/kubernetes/bin/flannel/ /run/flannel ; touch /run/flannel/docker;fi"

        if $(ssh $node systemctl status flanneld &>/dev/null); then
            echo -e "\033[32m$node Flanneld正在运行中，跳过复制可执行文件步骤..........\033[0m"
        else
            if $(ssh $node '[[ ! -e /usr/local/bin/flanneld ]]'); then
                scp $curPath/software/flanneld/flanneld $node:/usr/local/bin/
            fi

            if $(ssh $node '[[ ! -e /usr/local/bin/mk-docker-opts.sh ]]'); then
                scp $curPath/software/flanneld/mk-docker-opts.sh $node:/usr/local/bin/
            fi
        fi

        if $(ssh $node "[[ -f /etc/kubernetes/bin/flannel/flannel.pem && -f /etc/kubernetes/bin/flannel/flannel-key.pem ]]"); then
            echo -e "\033[32m$node 已存在Flanneld证书文件，跳过此步骤..........\033[0m"
        else
            scp /etc/kubernetes/bin/flannel/flannel* $node:/etc/kubernetes/bin/flannel/
        fi

        if $(ssh $node "[[ -f /etc/systemd/system/flanneld.service ]]"); then
            echo -e "\033[32m$node 已存在Flanneld Systemd Service文件，跳过此步骤..........\033[0m"
        else
            scp /etc/systemd/system/flanneld.service $node:/etc/systemd/system/flanneld.service
        fi

        scp /usr/local/etc/flanneld.conf $node:/usr/local/etc/flanneld.conf
        scp /tmp/docker.service $node:/usr/lib/systemd/system/docker.service

        ssh $node "systemctl disable flanneld;a=\$(ps -ef | grep -v grep | grep flanneld | awk '{print \$2}');if [ \"\$a\" != \"\" ];then echo \"\$a\"|xargs kill -9; fi;"
        ssh $node "systemctl daemon-reload ; systemctl enable docker flanneld"
        ssh $node "systemctl stop flanneld;systemctl daemon-reload && systemctl start flanneld &> /dev/null"
        ssh $node "systemctl daemon-reload && systemctl start docker &> /dev/null"

        # ssh $node "systemctl daemon-reload;systemctl enable docker flanneld && systemctl start flanneld ; systemctl restart flanneld && systemctl start docker ;systemctl restart docker"
        if [ $? ]; then
            echo -e "\033[32m $node Flanneld 启动成功\033[0m"
        else
            echo -e "\033[31m $node Flanneld 启动失败\033[0m"
        fi
    done
}

deployApiserver() {
    if [ -d /etc/kubernetes/bin/apiserver/ ]; then
        echo -e "\033[32m本地已存在/etc/kubernetes/bin/apiserver目录，跳过此步骤..........\033[0m"
    else
        mkdir -p /etc/kubernetes/bin/apiserver/ /etc/kubernetes/cfg
    fi

    if [ -d /etc/kubernetes/cfg/ ]; then
        echo -e "\033[32m本地已存在/etc/kubernetes/cfg目录，跳过此步骤..........\033[0m"
    else
        mkdir -p /etc/kubernetes/cfg
    fi

    if [[ ! -e /etc/kubernetes/cfg/token.csv ]]; then
        cat <<EOF >/etc/kubernetes/cfg/token.csv
${bootstrapToken},kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF
    fi
    cd /etc/kubernetes/bin/apiserver/
    cat <<EOF >/etc/kubernetes/bin/apiserver/apiserver-csr.json
{
    "CN": "kubernetes",
    "hosts": [
      "127.0.0.1",
      "${firstServiceIP}",
      "kubernetes",
      "kubernetes.default",
      "kubernetes.default.svc",
      "kubernetes.default.svc.cluster",
      "kubernetes.default.svc.cluster.local"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "ST": "GuangDong",
            "L": "GuangZhou",
            "O": "Dolphin",
            "OU": "Ops"
        }
    ]
}
EOF

    cat <<EOF >/etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
User=root
EnvironmentFile=/usr/local/etc/kube-apiserver.conf
ExecStart=/usr/local/bin/kube-apiserver \$KUBE_API_ARGS
Restart=on-failure
RestartSec=5
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    # 遍历所有节点,将所有节点的IP写入到csr.json里面的hosts字段
    # 这里本来可以只写master节点的IP，但考虑到新增apiserver需要重新生成csr文件，所以将用户输入的所有IP都写了进去
    nIndex=0
    nodeArrayLen=${#nodeArray[@]}
    while ((nIndex < nodeArrayLen)); do
        sed -i "4 a\"${nodeArray[$nIndex]}\"," /etc/kubernetes/bin/apiserver/apiserver-csr.json
        sed -i '5s/^/      /' /etc/kubernetes/bin/apiserver/apiserver-csr.json
        let nIndex+=1
    done

    sed -i "4 a\"${k8sVIP}\"," /etc/kubernetes/bin/apiserver/apiserver-csr.json
    sed -i '5s/^/      /' /etc/kubernetes/bin/apiserver/apiserver-csr.json
    if [[ ! -e /etc/kubernetes/bin/apiserver.pem && ! -e /etc/kubernetes/bin/apiserver/apiserver-key.pem ]]; then
        cfssl gencert -ca=/etc/kubernetes/ssl/ca/ca.pem \
            -ca-key=/etc/kubernetes/ssl/ca/ca-key.pem \
            -config=/etc/kubernetes/ssl/ca/ca-config.json \
            -profile=kubernetes apiserver-csr.json | cfssljson -bare apiserver
    fi

    for node in ${MasterIP[@]}; do
        echo >/tmp/kube-apiserver.conf
        cat <<EOF >/tmp/kube-apiserver.conf
KUBE_API_ARGS="--admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota,NodeRestriction \\
  --advertise-address=$node \\
  --bind-address=0.0.0.0 \\
  --insecure-port=0 \\
  --authorization-mode=Node,RBAC \\
  --runtime-config=rbac.authorization.k8s.io/v1beta1 \\
  --kubelet-https=true \\
  --token-auth-file=/etc/kubernetes/cfg/token.csv \\
  --service-cluster-ip-range=${serviceNet} \\
  --service-node-port-range=10000-60000 \\
  --tls-cert-file=/etc/kubernetes/bin/apiserver/apiserver.pem \\
  --tls-private-key-file=/etc/kubernetes/bin/apiserver/apiserver-key.pem \\
  --client-ca-file=/etc/kubernetes/ssl/ca/ca.pem \\
  --service-account-key-file=/etc/kubernetes/ssl/ca/ca-key.pem \\
  --etcd-cafile=/etc/kubernetes/ssl/ca/ca.pem \\
  --etcd-certfile=/etc/kubernetes/bin/apiserver/apiserver.pem \\
  --etcd-keyfile=/etc/kubernetes/bin/apiserver/apiserver-key.pem \\
  --storage-backend=etcd3 \\
  --etcd-servers=https://${MasterIP[0]}:2379,https://${MasterIP[1]}:2379,https://${MasterIP[2]}:2379 \\
  --enable-swagger-ui=true \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/lib/audit.log \\
  --event-ttl=1h \\
  --logtostderr=false \\
  --log-dir=/var/log/kubernetes/apiserver \\
  --v=2"
EOF
        if $(ssh $node "[[ -d /etc/kubernetes/bin/apiserver ]]"); then
            echo -e "\033[32m$node 已存在/etc/kubernetes/bin/apiserver目录，跳过此步骤..........\033[0m"
        else
            ssh $node mkdir -p /etc/kubernetes/bin/apiserver/
        fi

        if $(ssh $node "[[ -d /etc/kubernetes/cfg ]]"); then
            echo -e "\033[32m$node 已存在/etc/kubernetes/cfg目录，跳过此步骤..........\033[0m"
        else
            ssh $node mkdir -p /etc/kubernetes/cfg
        fi

        if $(ssh $node "[[ -d /var/log/kubernetes/apiserver  ]]"); then
            echo -e "\033[32m$node 已存在/var/log/kubernetes/apiserver目录，跳过此步骤..........\033[0m"
        else
            ssh $node mkdir -p /var/log/kubernetes/bootstrap
        fi

        if $(ssh $node "[[ -f /etc/kubernetes/cfg/token.csv ]]"); then
            echo -e "\033[32m$node 已存在/etc/kubernetes/cfg/token.csv文件，跳过此步骤..........\033[0m"
        else
            scp /etc/kubernetes/cfg/token.csv $node:/etc/kubernetes/cfg/
        fi

        if $(ssh $node "[[ -f /etc/kubernetes/bin/apiserver/apiserver-key.pem ]]"); then
            echo -e "\033[32m$node 已存在kube-apiserver证书私钥文件，跳过此步骤..........\033[0m"
        else
            scp /etc/kubernetes/bin/apiserver/apiserver* $node:/etc/kubernetes/bin/apiserver/
        fi

        if $(ssh $node "[[ -f /etc/systemd/system/kube-apiserver.service ]]"); then
            echo -e "\033[32m$node 已存在kube-apiserver service文件，跳过此步骤..........\033[0m"
        else
            scp /etc/systemd/system/kube-apiserver.service $node:/etc/systemd/system/kube-apiserver.service &
        fi

        scp /tmp/kube-apiserver.conf $node:/usr/local/etc/kube-apiserver.conf
        ssh $node "systemctl enable kube-apiserver && systemctl start kube-apiserver"
        if [ $? ]; then
            echo -e "\033[32m $node kube-apiserver 启动成功\033[0m"
        else
            echo -e "\033[31m $node kube-apiserver 启动失败，请检查日志文件\033[0m"
        fi
    done
}

deployControllerManager() {
    if [ ! -d /etc/kubernetes/bin/controller-manager ]; then mkdir -p /etc/kubernetes/bin/controller-manager; fi
    cd /etc/kubernetes/bin/controller-manager
    cat <<EOF >/etc/kubernetes/bin/controller-manager/controller-manager-csr.json
    {
        "CN": "system:kube-controller-manager",
        "hosts": [
          "${MasterIP[0]}",
          "${MasterIP[1]}",
          "${MasterIP[2]}"
        ],
        "key": {
            "algo": "rsa",
            "size": 2048
        },
        "names": [
            {
                "C": "CN",
                "ST": "GuangDong",
                "L": "GuangZhou",
                "O": "system:kube-controller-manager",
                "OU": "Ops"
            }
        ]
    }
EOF
    if [[ ! -e /etc/kubernetes/bin/controller-manager/controller-manager.pem && ! -e /etc/kubernetes/bin/controller-manager/controller-manager-key.pem ]]; then
        cfssl gencert -ca=/etc/kubernetes/ssl/ca/ca.pem -ca-key=/etc/kubernetes/ssl/ca/ca-key.pem -config=/etc/kubernetes/ssl/ca/ca-config.json -profile=kubernetes /etc/kubernetes/bin/controller-manager/controller-manager-csr.json | cfssljson -bare controller-manager
    fi

    cat <<EOF >/etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target
After=kube-apiserver.service

[Service]
EnvironmentFile=/usr/local/etc/kube-controller-manager.conf
ExecStart=/usr/local/bin/kube-controller-manager \$KUBE_CONTROLLER_MANAGER_ARGS
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    cat <<EOF >/usr/local/etc/kube-controller-manager.conf
KUBE_CONTROLLER_MANAGER_ARGS="--master=https://${k8sVIP}:8443 \\
  --kubeconfig=/etc/kubernetes/bin/controller-manager/controller-manager.conf \\
  --allocate-node-cidrs=true \\
  --service-cluster-ip-range=${serviceNet} \\
  --cluster-cidr=${podNet} \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/etc/kubernetes/ssl/ca/ca.pem \\
  --cluster-signing-key-file=/etc/kubernetes/ssl/ca/ca-key.pem \\
  --service-account-private-key-file=/etc/kubernetes/ssl/ca/ca-key.pem \\
  --root-ca-file=/etc/kubernetes/ssl/ca/ca.pem \\
  --use-service-account-credentials=true \\
  --controllers=*,bootstrapsigner,tokencleaner \\
  --leader-elect=true \\
  --logtostderr=false \\
  --log-dir=/var/log/kubernetes/controller-manager \\
  --v=2"
EOF

    kubectl config set-cluster kubernetes \
        --certificate-authority=/etc/kubernetes/ssl/ca/ca.pem \
        --embed-certs=true \
        --server=https://${k8sVIP}:8443 \
        --kubeconfig=/etc/kubernetes/bin/controller-manager/controller-manager.conf
    kubectl config set-credentials system:kube-controller-manager \
        --client-certificate=/etc/kubernetes/bin/controller-manager/controller-manager.pem \
        --embed-certs=true \
        --client-key=/etc/kubernetes/bin/controller-manager/controller-manager-key.pem \
        --kubeconfig=/etc/kubernetes/bin/controller-manager/controller-manager.conf
    kubectl config set-context system:kube-controller-manager@kubernetes \
        --cluster=kubernetes \
        --user=system:kube-controller-manager \
        --kubeconfig=/etc/kubernetes/bin/controller-manager/controller-manager.conf
    kubectl config use-context system:kube-controller-manager@kubernetes --kubeconfig=/etc/kubernetes/bin/controller-manager/controller-manager.conf

    for node in ${MasterIP[@]}; do
        if $(ssh $node "[[ -d /etc/kubernetes/bin/controller-manager ]]"); then
            echo -e "\033[32m$node 已存在/etc/kubernetes/bin/controller-manager目录,跳过此步骤..........\033[0m"
        else
            ssh $node mkdir -p /etc/kubernetes/bin/controller-manager
        fi

        if $(ssh $node "[[ -d /var/log/kubernetes/controller-manager/ ]]"); then
            echo -e "\033[32m$node 已存在/var/log/kubernetes/controller-manager目录,跳过此步骤..........\033[0m"
        else
            ssh $node mkdir -p /etc/kubernetes/bin/controller-manager
        fi

        if $(ssh $node "[[ -f /etc/kubernetes/bin/controller-manager/controller-manager-key.pem ]]"); then
            echo -e "\033[32m$node 已存在kube-controller-manager证书私钥文件,跳过此步骤..........\033[0m"
        else
            scp /etc/kubernetes/bin/controller-manager/* $node:/etc/kubernetes/bin/controller-manager/
        fi

        # if $(ssh $ "[[ -f /etc/kubernetes/bin/controller-manager.conf ]]");then
        #     echo -e "\033[32m$node 已存在kube-controller-manager证书私钥文件,跳过此步骤..........\033[0m"
        # else
        #     scp /usr/local/etc/kube-controller-manager.conf $node:/usr/local/etc/kube-controller-manager.conf &
        # fi

        scp /usr/local/etc/kube-controller-manager.conf $node:/usr/local/etc/kube-controller-manager.conf

        if $(ssh $node "[[ -f /etc/systemd/system/kube-controller-manager.service ]]"); then
            echo -e "\033[32m$node 已存在kube-controller-manager systemd service文件,跳过此步骤..........\033[0m"
        else
            scp /etc/systemd/system/kube-controller-manager.service $node:/etc/systemd/system/kube-controller-manager.service
        fi

        ssh $node "systemctl enable kube-controller-manager && systemctl start kube-controller-manager"
        if [ $? ]; then
            echo -e "\033[32m $node kube-controller-manager 启动成功\033[0m"
        else
            echo -e "\033[31m $node kube-controller-manager 启动失败，请检查日志文件\033[0m"
        fi
    done
}

deployScheduler() {
    if [[ ! -d /etc/kubernetes/bin/scheduler ]]; then mkdir -p /etc/kubernetes/bin/scheduler/; fi
    # /var/log/kubernetes/scheduler
    cd /etc/kubernetes/bin/scheduler/
    cat <<EOF >/etc/kubernetes/bin/scheduler/scheduler-csr.json
{
    "CN": "system:kube-scheduler",
    "hosts": [
      "${MasterIP[0]}",
      "${MasterIP[1]}",
      "${MasterIP[2]}"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "ST": "GuangDong",
            "L": "GuangZhou",
            "O": "system:kube-scheduler",
            "OU": "Ops"
        }
    ]
}
EOF

    if [[ ! -e /etc/kubernetes/bin/scheduler/scheduler-key.pem && ! -e /etc/kubernetes/bin/scheduler/scheduler.pem ]]; then
        cfssl gencert -ca=/etc/kubernetes/ssl/ca/ca.pem \
            -ca-key=/etc/kubernetes/ssl/ca/ca-key.pem \
            -config=/etc/kubernetes/ssl/ca/ca-config.json \
            -profile=kubernetes /etc/kubernetes/bin/scheduler/scheduler-csr.json | cfssljson -bare scheduler
    fi

    if [[ ! -f /etc/kubernetes/scheduler/scheduler.conf ]]; then
        kubectl config set-cluster kubernetes \
            --certificate-authority=/etc/kubernetes/ssl/ca/ca.pem \
            --embed-certs=true \
            --server=https://${k8sVIP}:8443 \
            --kubeconfig=/etc/kubernetes/bin/scheduler/scheduler.conf
        kubectl config set-credentials system:kube-scheduler \
            --client-certificate=/etc/kubernetes/bin/scheduler/scheduler.pem \
            --embed-certs=true \
            --client-key=/etc/kubernetes/bin/scheduler/scheduler-key.pem \
            --kubeconfig=/etc/kubernetes/bin/scheduler/scheduler.conf
        kubectl config set-context system:kube-scheduler@kubernetes \
            --cluster=kubernetes \
            --user=system:kube-scheduler \
            --kubeconfig=scheduler.conf
        kubectl config use-context system:kube-scheduler@kubernetes --kubeconfig=scheduler.conf
    fi

    cat <<EOF >/etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target
After=kube-apiserver.service

[Service]
EnvironmentFile=/usr/local/etc/kube-scheduler.conf
ExecStart=/usr/local/bin/kube-scheduler \$KUBE_SCHEDULER_ARGS
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    cat <<EOF >/usr/local/etc/kube-scheduler.conf
KUBE_SCHEDULER_ARGS="--master=https://${k8sVIP}:8443 \
  --kubeconfig=/etc/kubernetes/bin/scheduler/scheduler.conf \
  --leader-elect=true \
  --logtostderr=false \
  --log-dir=/var/log/kubernetes/scheduler \
  --v=2"
EOF

    for node in ${MasterIP[@]}; do
        if $(ssh $node "[[ -d /etc/kubernetes/bin/scheduler ]]"); then
            echo -e "\033[32m$node 已存在/etc/kubernetes/bin/scheduler/目录,跳过此步骤..........\033[0m"
        else
            ssh $node mkdir -p /etc/kubernetes/bin/scheduler/
        fi

        if $(ssh $node "[[ -d /etc/kubernetes/bin/scheduler ]]"); then
            echo -e "\033[32m$node 已存在/etc/kubernetes/bin/scheduler/目录,跳过此步骤..........\033[0m"
        else
            ssh $node mkdir -p /var/log/kubernetes/scheduler/
        fi

        if $(ssh $node "[[ -f /etc/kubernetes/bin/scheduler/scheduler-key.pem ]]"); then
            echo -e "\033[32m$node 已存在kube-scheduler证书私钥文件,跳过此步骤..........\033[0m"
        else
            scp /etc/kubernetes/bin/scheduler/* $node:/etc/kubernetes/bin/scheduler/
        fi

        if $(ssh $node "[[ -f /etc/systemd/system/kube-scheduler.service ]]"); then
            echo -e "\033[32m$node 已存在kube-scheduler systemd service文件,跳过此步骤..........\033[0m"
        else
            scp /etc/systemd/system/kube-scheduler.service $node:/etc/systemd/system/
        fi

        scp /usr/local/etc/kube-scheduler.conf $node:/usr/local/etc/
        ssh $node "systemctl enable kube-scheduler && systemctl start kube-scheduler"
        if [ $? ]; then
            echo -e "\033[32m $node kube-scheduler 启动成功\033[0m"
        else
            echo -e "\033[31m $node kube-scheduler 启动失败，请检查日志文件\033[0m"
        fi
    done
}

deployKubelet() {
    kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap &
    cd /etc/kubernetes/cfg/
    echo -e "\033[32mToken是:${bootstrapToken}\033[0m"
    echo
    if [[ -f /etc/kubernetes/cfg/boostrap.kubeconfig ]]; then
        echo -e "\033[32m已存在bootstrap.kubeconfig，跳过此步骤..........\033[0m"
    else
        kubectl config set-cluster kubernetes --certificate-authority=/etc/kubernetes/ssl/ca/ca.pem --embed-certs=true --server=https://${k8sVIP}:8443 --kubeconfig=bootstrap.kubeconfig
        kubectl config set-credentials kubelet-bootstrap --token=${bootstrapToken} --kubeconfig=bootstrap.kubeconfig
        kubectl config set-context default --cluster=kubernetes --user=kubelet-bootstrap --kubeconfig=bootstrap.kubeconfig
        kubectl config use-context default --kubeconfig=bootstrap.kubeconfig
    fi

    cat <<EOF >/etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=/var/lib/kubelet
EnvironmentFile=/usr/local/etc/kubelet.conf
ExecStart=/usr/local/bin/kubelet \$KUBELET_ARGS
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    for node in ${NodeIP[@]}; do
        cat <<EOF >/tmp/kubelet.conf
KUBELET_ARGS="--address=0.0.0.0 \\
  --hostname-override=$node \\
  --pod-infra-container-image=registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.0 \\
  --bootstrap-kubeconfig=/etc/kubernetes/cfg/bootstrap.kubeconfig \\
  --kubeconfig=/etc/kubernetes/cfg/kubelet.kubeconfig \\
  --cert-dir=/etc/kubernetes/cfg \\
  --cluster-dns=${clusterDnsIP} \\
  --cluster-domain=cluster.local. \\
  --serialize-image-pulls=false \\
  --fail-swap-on=false \\
  --logtostderr=false \\
  --log-dir=/var/log/kubernetes/kubelet \\
  --v=2"
EOF
        if $(ssh $node "[[ -d /etc/kubernetes/cfg/ ]]"); then
            echo -e "\033[32m$node 已存在/etc/kubernetes/cfg目录,跳过此步骤..........\033[0m"
        else
            ssh $node "mkdir -p /etc/kubernetes/cfg/"
        fi

        if $(ssh $node "[[ -d /var/lib/kubelet ]]"); then
            echo -e "\033[32m$node 已存在/var/lib/kubelet目录,跳过此步骤..........\033[0m"
        else
            ssh $node "mkdir -p /var/lib/kubelet"
        fi

        if $(ssh $node "[[ -d /var/log/kubernetes/kubelet ]]"); then
            echo -e "\033[32m$node 已存在/var/log/kubernetes/kubelet目录,跳过此步骤..........\033[0m"
        else
            ssh $node "mkdir -p /var/log/kubernetes/kubelet"
        fi

        if $(ssh $node "[[ -f /etc/systemd/system/kubelet.service ]]"); then
            echo -e "\033[32m$node 已存在kubelet systemd service文件,跳过此步骤..........\033[0m"
        else
            scp /etc/systemd/system/kubelet.service $node:/etc/systemd/system/
        fi

        if $(ssh $node "[[ -f /etc/kubernetes/cfg/bootstrap.kubeconfig ]]"); then
            echo -e "\033[32m$node 已存在kubelet bootstrap kubeconfig文件,跳过此步骤..........\033[0m"
        else
            scp /etc/kubernetes/cfg/bootstrap.kubeconfig $node:/etc/kubernetes/cfg/
        fi
        scp /tmp/kubelet.conf $node:/usr/local/etc/
        ssh $node "systemctl enable kubelet && systemctl start kubelet"
        if [ $? ]; then
            echo -e "\033[32m $node kubelet 启动成功\033[0m"
        else
            echo -e "\033[31m $node kubelet 启动失败，请检查日志文件\033[0m"
        fi
    done

    # 确保在所有节点都发出了CSR之后再进行approve操作
    sleep 10
    if [ $? ]; then
        for node in $(kubectl get csr | awk 'NR>1{print $1}'); do kubectl certificate approve $node; done
    else
        echo -e "\033[31m 未找到有CSR签署请求，请检查kubelet日志,退出脚本请按Ctrl+C\033[0m"
    fi

}

deployKubeProxy() {
    if [ ! -d /etc/kubernetes/bin/proxy ]; then mkdir -p /etc/kubernetes/bin/proxy; fi
    cd /etc/kubernetes/bin/proxy
    cat <<EOF >proxy-csr.json
{
    "CN": "system:kube-proxy",
    "hosts": [],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "ST": "GuangDong",
            "L": "GuangZhou",
            "O": "system:kube-proxy",
            "OU": "Ops"
        }
    ]
}
EOF

    if [[ ! -e /etc/kubernetes/bin/proxy/proxy.pem && ! -e /etc/kubernetes/bin/proxy/proxy-key.pem ]]; then
        cfssl gencert -ca=/etc/kubernetes/ssl/ca/ca.pem -ca-key=/etc/kubernetes/ssl/ca/ca-key.pem -config=/etc/kubernetes/ssl/ca/ca-config.json -profile=kubernetes proxy-csr.json | cfssljson -bare proxy
    fi

    if [[ -f /etc/kubernetes/bin/proxy/proxy.kubeconfig ]]; then
        echo -e "\033[32m$node 已存在kube-proxy文件,跳过此步骤..........\033[0m"
    else
        kubectl config set-cluster kubernetes --certificate-authority=/etc/kubernetes/ssl/ca/ca.pem --embed-certs=true --server=https://${k8sVIP}:8443 --kubeconfig=proxy.kubeconfig
        kubectl config set-credentials system:kube-proxy --client-certificate=/etc/kubernetes/bin/proxy/proxy.pem --embed-certs=true --client-key=/etc/kubernetes/bin/proxy/proxy-key.pem --kubeconfig=proxy.kubeconfig
        kubectl config set-context system:kube-proxy@kubernetes --cluster=kubernetes --user=system:kube-proxy --kubeconfig=proxy.kubeconfig
        kubectl config use-context system:kube-proxy@kubernetes --kubeconfig=proxy.kubeconfig
    fi

    cat <<EOF >/etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
WorkingDirectory=/var/lib/kube-proxy
EnvironmentFile=/usr/local/etc/kube-proxy.conf
ExecStart=/usr/local/bin/kube-proxy \$KUBE_PROXY_ARGS
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    for node in ${NodeIP[@]}; do
        cat <<EOF >/tmp/kube-proxy.conf
KUBE_PROXY_ARGS="--bind-address=0.0.0.0 \\
  --hostname-override=$ \\
  --cluster-cidr=${serviceNet} \\
  --kubeconfig=/etc/kubernetes/bin/proxy/proxy.kubeconfig \\
  --logtostderr=false \\
  --log-dir=/var/log/kubernetes/proxy \\
  --proxy-mode=ipvs \\
  --ipvs-scheduler=wrr \\
  --ipvs-min-sync-period=5s \\
  --ipvs-sync-period=5s \\
  --masquerade-all \\
  --v=2"
EOF

        if $(ssh $node "[[ -d /etc/kubernetes/bin/proxy ]]"); then
            echo -e "\033[32m$node 已存在/etc/kubernetes/bin/proxy/目录,跳过此步骤..........\033[0m"
        else
            ssh $node "mkdir -p /etc/kubernetes/bin/proxy/" /var/lib/kube-proxy
        fi

        if $(ssh $node "[[ -d /var/lib/kube-proxy ]]"); then
            echo -e "\033[32m$node 已存在/var/lib/kube-proxy目录,跳过此步骤..........\033[0m"
        else
            ssh $node "mkdir -p /var/lib/kube-proxy"
        fi

        if $(ssh $node "[[ -d /var/log/kubernetes/proxy ]]"); then
            echo -e "\033[32m$node 已存在/var/log/kubernetes/proxy/目录,跳过此步骤..........\033[0m"
        else
            ssh $node "mkdir -p /var/log/kubernetes/proxy/"
        fi

        if $(ssh $node "[[ -d /var/lib/kube-proxy ]]"); then
            echo -e "\033[32m$node 已存在/var/lib/kube-proxy目录,跳过此步骤..........\033[0m"
        else
            ssh $node "mkdir -p /var/lib/kube-proxy"
        fi

        if $(ssh $node "[[ -f /etc/kubernetes/bin/proxy/proxy-key.pem ]]"); then
            echo -e "\033[32m$node 已存在kube-proxy证书私钥文件,跳过此步骤..........\033[0m"
        else
            scp /etc/kubernetes/bin/proxy/* $node:/etc/kubernetes/bin/proxy/
        fi

        scp /tmp/kube-proxy.conf $node:/usr/local/etc/

        if $(ssh $node "[[ -f /etc/systemd/system/kube-proxy.service ]]"); then
            echo -e "\033[32m$node 已存在kube-proxy systemd service文件,跳过此步骤..........\033[0m"
        else
            scp /etc/systemd/system/kube-proxy.service $node:/etc/systemd/system/
        fi

        ssh $node "systemctl enable kube-proxy && systemctl start kube-proxy"
        if [ $? ]; then
            echo -e "\033[32m $node kube-proxy 启动成功\033[0m"
        else
            echo -e "\033[31m $node kube-proxy 启动失败，请检查日志文件\033[0m"
        fi
    done
}

deployIngressController() {
    mkdir -p $curPath/yaml
    echo -e "\033[32m 正在部署nginx-ingress-controller.. \033[0m"
    if [ ! -e $curPath/images/nginx-ingress-controller-0.27.1.tar.gz ]; then
        docker pull registry.aliyuncs.com/google_containers/nginx-ingress-controller:0.27.1
        docker tag registry.aliyuncs.com/google_containers/nginx-ingress-controller:0.27.1 quay.io/kubernetes-ingress-controller/nginx-ingress-controller:master
        docker save -o $curPath/images/nginx-ingress-controller-0.27.1.tar quay.io/kubernetes-ingress-controller/nginx-ingress-controller:master
    fi
    if [ ! -e $curPath/yaml/nginx-ingress-controller-mandatory.yaml ]; then
        wget https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.27.1/deploy/static/mandatory.yaml -O $curPath/yaml/nginx-ingress-controller-mandatory.yaml
    fi
    if [ ! -e $curPath/yaml/nginx-ingress-controller-service.yaml ]; then
        wget https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.27.1/deploy/static/provider/baremetal/service-nodeport.yaml -O $curPath/yaml/nginx-ingress-controller-service.yaml
    fi
    for node in ${NodeIP[@]}; do
        scp $curPath/images/nginx-ingress-controller-0.27.1.tar.gz $curPath/yaml/nginx-ingress-controller-mandatory.yaml $node:/tmp/
        ssh $node "docker image load -i /tmp/nginx-ingress-controller-0.27.1.tar.gz"
    done
    kubectl apply -f /tmp/nginx-ingress-controller-mandatory.yaml
    kubectl apply -f /tmp/nginx-ingress-controller-service.yaml
    sleep 5
    kubectl scale deploy -n ingress-nginx nginx-ingress-controller --replicas=${#NodeIP[@]}
}

deployCoreDNS() {
    echo
    echo -e "\033[32m 正在部署CoreDNS..... \033[0m"
    if [ ! -e $curPath/software/coredns-deployment-1.8.0.tar.gz ]; then
        git clone https://github.com/coredns/deployment.git $curPath/software/deployment
        cd $curPath/software
        tar -cvf coredns-deployment-1.8.0.tar.gz ./deployment/*
        rm -rf $curPath/software/deployment
        tar xvf $curPath/software/coredns-deployment-1.8.0.tar.gz -C /tmp
    fi

    if [ ! -e $curPath/images/coredns-image-1.8.0.tar.gz ]; then
        docker pull registry.aliyuncs.com/google_containers/coredns:1.8.0
        docker tag registry.aliyuncs.com/google_containers/coredns:1.8.0 coredns/coredns:1.8.0
        docker save -o $curPath/images/coredns-image-1.8.0.tar.gz coredns/coredns:1.8.0
    fi
    for node in ${NodeIP[@]}; do
        $curPath/images/coredns-image-1.8.0.tar.gz $node:/tmp/
        ssh $node exec docker image load -i /tmp/coredns-image-1.8.0.tar.gz
    done
    bash /tmp/deployment-master/kubernetes/deploy.sh -i ${clusterDnsIP} -s | kubectl apply -f -
    sleep 5
    kubectl scale deploy -n kube-system coredns --replicas=${#NodeIP[@]}
}

autoSSHCopy
preparation
deployHaproxyKeepalived
deployETCD
setKubectl
deployFlannel
# deployApiserver
# deployControllerManager
# deployScheduler
# deployKubelet
# deployKubeProxy
# deployIngressController
# deployCoreDNS
