master01='192.168.33.100'
node01='192.168.33.101'
node02='192.168.33.102'
node03='192.168.33.103'
master_nodes=(master01)
all_nodes=(master01 node01 node02 node03)
etcd_nodes=(master01 node01 node02)

k8s_version='v1.20.0'

inArray=0

curPath=$(readlink -f "$(dirname "$0")")
if [[ "$?" == "1" ]]; then
    curPath=/root
fi

echo $curPath

IsContains() {
    newarray=$1
    inArray=0
    for item in ${newarray[@]}; do
        if [ $item == $1 ]; then
            inArray=1
            echo 'contains' $item
            break
        fi
    done
}

init() {
    mv /etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel.repo.bak
    mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup
    wget -O /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
    wget -O /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo
    # 非阿里云ECS用户会出现 Couldn't resolve host 'mirrors.cloud.aliyuncs.com' 信息，不影响使用，可以修改配置
    sed -i -e '/mirrors.cloud.aliyuncs.com/d' -e '/mirrors.aliyuncs.com/d' /etc/yum.repos.d/CentOS-Base.repo
    systemctl stop firewalld
    systemctl disable firewalld
    systemctl stop etcd
    systemctl disable etcd
    systemctl stop kube-apiserver
    systemctl disable kube-apiserver

    systemctl stop kube-controller-manager
    systemctl disable kube-controller-manager
    systemctl stop kube-proxy
    systemctl disable kube-proxy
    systemctl stop kubelet
    systemctl disable kube-scheduler
    systemctl stop kube-scheduler
    systemctl disable kube-scheduler

    ps -ef | grep ssh | grep install_docker | awk '{print $2}' | xargs kill -9
    ps -ef | grep -v 'grep' | grep etcd | awk '{print $2}' | xargs kill -9
    ps -ef | grep -v 'grep' | grep etcd
    sed -i 's/enforcing/disabled/' /etc/selinux/config
    setenforce 0
    swapoff -a
    sed -ri 's/.*swap.*/#&/' /etc/fstab
    pkill -9 etcd

    rm -rf /opt/kubernetes/*
    rm -rf /var/lib/etcd/*
    rm -rf /etc/systemd/system/etcd.service
    rm -rf /usr/lib/systemd/system/kube-apiserver.service
    rm -rf /usr/lib/systemd/system/kube-controller-manager.service
    rm -rf /usr/bin/kube*
    mkdir -p /opt/kubernetes/{cfg,bin,ssl,log}
    mkdir -p /var/lib/etcd/
    rm -rf /etc/systemd/system/multi-user.target.wants

    rm -rf /opt/etcd/*
    rm -rf /usr/lib/systemd/system/kubelet.service.d
    rm -rf /var/lib/etcd/*
    rm -rf /etc/systemd/system/etcd.service
    mkdir -p /opt/etcd/{cfg,bin,ssl,log}
    mkdir -p /var/lib/etcd/
    yum install ntpdate lrzsz net-tools -y
    ntpdate ntp1.aliyun.com
}

get_ip() {
    # $(eval echo $(eval echo '$'"$(hostname)"))
    a1=eval echo '$'"$1"
    ip=$(eval echo $a1)
    echo $ip
}

install_docker() {
    pkill -9 yum
    yum remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine -y
    #     echo -e '[kubernetes]
    # name=Kubernetes Repo
    # baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
    # gpgcheck=1
    # gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
    # enabled=1
    # ' >/etc/yum.repos.d/kubernetes.repo
    # wget https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
    # yum install -y kubelet-1.20.0 kubeadm-1.20.0 kubectl-1.20.0
    # systemctl enable kubelet
    # kubeadm init   --apiserver-advertise-address=10.10.10.225   --image-repository registry.aliyuncs.com/google_containers   --kubernetes-version v1.20.0   --service-cidr=10.96.0.0/12   --pod-network-cidr=10.244.0.0/16   --ignore-preflight-errors=all

    # rpm --import rpm-package-key.gpg
    wget -O /etc/yum.repos.d/docker-ce.repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

    yum repolist
    yum clean all
    yum makecache
    # yum install -y epel-release
    yum install docker-ce -y
    echo -e '{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://quay.mirrors.ustc.edu.cn",
    "https://registry.docker-cn.com",
    "http://hub-mirror.c.163.com",
    "https://b9pmyelo.mirror.aliyuncs.com"
  ]
}' >/etc/docker/daemon.json
    systemctl start docker
    systemctl enable docker
    systemctl status docker

}

install_python39() {
    cd $curPath
    yum install automake build-essential git zlib* openssl* libffi* libssl* libsqlite3* -y
    wget https://www.python.org/ftp/python/3.9.2/Python-3.9.2.tgz
    tar -zxvf Python-3.9.2.tgz
    cd Python-3.9.2
    ./configure --with-ssl && make -j 16 && make install
    cd $curPath
    rm -rf ./Python-3.9.2*
}

set_proxy() {
    # export http_proxy=http://10.10.10.20:1081
    # export http_proxy=https://10.10.10.20:1081
    # export http_proxy=http://10.10.16.89:1087
    # export https_proxy=https://10.10.16.89:1087
    export http_proxy=http://192.168.0.104:8080
    export https_proxy=https://192.168.0.104:8080
    export http_proxy=http://192.168.0.104:1087
    export https_proxy=https://192.168.0.104:1087
    export HTTPS_PROXY=$http_proxy
    export HTTP_PROXY=$http_proxy
    if which git >/dev/null; then
        git config --global http.proxy $http_proxy
        git config --global https.proxy $http_proxy
    fi
    if which npm >/dev/null; then
        npm config set proxy=$http_proxy
        npm config set registry=http://registry.npmjs.org
    fi
}

unset_proxy() {
    unset https_proxy
    unset http_proxy
    unset all_proxy
    unset HTTPS_PROXY
    unset HTTP_PROXY

    if which git >/dev/null; then
        git config --global --unset http.proxy
        git config --global --unset https.proxy
    fi
    if which npm >/dev/null; then
        npm config delete proxy
        npm config delete registry
    fi
}

install_software() {
    set_proxy
    mkdir -p $curPath/cfssl
    if [ -f "./cfssl/cfssl-certinfo_linux-amd64" ]; then
        echo "cfssl-certinfo_linux-amd64 exist"
    else
        wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64 -O $curPath/cfssl/cfssl-certinfo_linux-amd64
    fi
    if [ -f "./cfssl/cfssljson_linux-amd64" ]; then
        echo "cfssljson_linux-amd64  exist"
    else
        wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 -O $curPath/cfssl/cfssljson_linux-amd64
    fi
    if [ -f "./cfssl/cfssl_linux-amd64" ]; then
        echo "cfssl_linux-amd64 exist"
    else
        wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 -O $curPath/cfssl/cfssl_linux-amd64
    fi
    if [ -f "calico.yaml" ]; then
        echo "calico.yaml exist"
    else
        # wget https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
        wget https://docs.projectcalico.org/v3.15/manifests/calico.yaml
    fi
    # docker.io/
    sed -i 's/docker.io\///g' $curPath/calico.yaml
    sed -i 's/v3.15.5/v3.15.1/g' $curPath/calico.yaml
    rm -rf /usr/local/bin/cfssl*
    cp $curPath/cfssl/cfssl-certinfo_linux-amd64 /usr/local/bin/cfssl-certinfo
    cp $curPath/cfssl/cfssljson_linux-amd64 /usr/local/bin/cfssljson
    cp $curPath/cfssl/cfssl_linux-amd64 /usr/local/bin/cfssl

    chmod +x /usr/local/bin/cfssl*
    mkdir software
    if [ -f "./software/kubernetes.tar.gz" ]; then
        echo "kubernetes.tar.gz exist"
    else
        wget https://dl.k8s.io/${k8s_version}/kubernetes.tar.gz -O $curPath/software/kubernetes.tar.gz
    fi

    if [ -f "./software/kubernetes-client-linux-amd64.tar.gz" ]; then
        echo "kubernetes-client-linux-amd64.tar.gz exist"
    else
        wget https://dl.k8s.io/${k8s_version}/kubernetes-client-linux-amd64.tar.gz -O $curPath/software/kubernetes-client-linux-amd64.tar.gz
    fi
    if [ -f "./software/kubernetes-server-linux-amd64.tar.gz" ]; then
        echo "kubernetes-server-linux-amd64.tar.gz exist"
    else
        wget https://dl.k8s.io/${k8s_version}/kubernetes-server-linux-amd64.tar.gz -O $curPath/software/kubernetes-server-linux-amd64.tar.gz
    fi
    if [ -f "./software/kubernetes-node-linux-amd64.tar.gz" ]; then
        echo "kubernetes-node-linux-amd64.tar.gz exist"
    else
        wget https://dl.k8s.io/${k8s_version}/kubernetes-node-linux-amd64.tar.gz -O $curPath/software/kubernetes-node-linux-amd64.tar.gz
    fi

    if [ -f "./software/etcd-v3.3.11-linux-amd64.tar.gz" ]; then
        echo "etcd-v3.3.11-linux-amd64.tar.gz exist"
    else
        wget https://github.com/coreos/etcd/releases/download/v3.3.11/etcd-v3.3.11-linux-amd64.tar.gz -O $curPath/software/etcd-v3.3.11-linux-amd64.tar.gz
    fi

    unset_proxy
    rm -rf $curPath/software/kubernetes
    rm -rf $curPath/software/etcd-v3.3.11-linux-amd64
    cd $curPath/software
    tar zxf kubernetes.tar.gz
    tar zxf kubernetes-client-linux-amd64.tar.gz
    tar zxf kubernetes-server-linux-amd64.tar.gz
    tar zxf kubernetes-node-linux-amd64.tar.gz

    tar zxf etcd-v3.3.11-linux-amd64.tar.gz

    for node in ${etcd_nodes[@]}; do
        scp etcd-v3.3.11-linux-amd64/etcd* $node:/opt/etcd/bin/
    done

    for node in ${master_nodes[@]}; do
        # hostnamectl set-hostname k8s-master
        scp kubernetes/server/bin/kube-apiserver $node:/opt/kubernetes/bin
        scp kubernetes/server/bin/kube-scheduler $node:/opt/kubernetes/bin
        scp kubernetes/server/bin/kube-controller-manager $node:/opt/kubernetes/bin
    done
    for node in ${all_nodes[@]}; do
        scp kubernetes/server/bin/kubectl $node:/usr/bin/
        scp kubernetes/server/bin/kubelet $node:/opt/kubernetes/bin
        scp kubernetes/server/bin/kube-proxy $node:/opt/kubernetes/bin
    done
    rm -rf $curPath/software/etcd-v3.3.11-linux-amd64
    rm -rf $curPath/software/kubernetes
    cd $curPath
}

install_k8s_worker() {
    # 部署kubelet
    # 1. 创建配置文件
    cd $curPath
    rm -f /opt/kubernetes/cfg/kubelet.kubeconfig
    rm -f /opt/kubernetes/ssl/kubelet*
    echo -e 'KUBELET_OPTS="--logtostderr=false \
  --v=2 \
  --log-dir=/opt/kubernetes/log \
  --hostname-override=k8s-'$(hostname)' \
  --network-plugin=cni \
  --kubeconfig=/opt/kubernetes/cfg/kubelet.kubeconfig \
  --bootstrap-kubeconfig=/opt/kubernetes/cfg/bootstrap.kubeconfig \
  --config=/opt/kubernetes/cfg/kubelet-config.yml \
  --cert-dir=/opt/kubernetes/ssl \
  --pod-infra-container-image=registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.2"' >/opt/kubernetes/cfg/kubelet.conf

    # 2. 配置参数文件
    cat >/opt/kubernetes/cfg/kubelet-config.yml <<EOF
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
address: 0.0.0.0
port: 10250
readOnlyPort: 10255
cgroupDriver: cgroupfs
clusterDNS:
- 10.0.0.2
clusterDomain: cluster.local
failSwapOn: false
authentication:
  anonymous:
    enabled: false
  webhook:
    cacheTTL: 2m0s
    enabled: true
  x509:
    clientCAFile: /opt/kubernetes/ssl/ca.pem
authorization:
  mode: Webhook
  webhook:
    cacheAuthorizedTTL: 5m0s
    cacheUnauthorizedTTL: 30s
evictionHard:
  imagefs.available: 15%
  memory.available: 100Mi
  nodefs.available: 10%
  nodefs.inodesFree: 5%
maxOpenFiles: 1000000
maxPods: 110
EOF
    KUBE_CONFIG="/opt/kubernetes/cfg/bootstrap.kubeconfig"
    KUBE_APISERVER="https://$master01:6443"  # apiserver IP:PORT
    TOKEN="c47ffb939f5ca36231d9e3121a252940" # 与token.csv里保持一致

    #  3. 生成kubelet初次加入集群引导kubeconfig文件
    kubectl config set-cluster kubernetes \
        --certificate-authority=/opt/kubernetes/ssl/ca.pem \
        --embed-certs=true \
        --server=${KUBE_APISERVER} \
        --kubeconfig=${KUBE_CONFIG}
    kubectl config set-credentials "kubelet-bootstrap" \
        --token=${TOKEN} \
        --kubeconfig=${KUBE_CONFIG}
    kubectl config set-context default \
        --cluster=kubernetes \
        --user="kubelet-bootstrap" \
        --kubeconfig=${KUBE_CONFIG}
    kubectl config use-context default --kubeconfig=${KUBE_CONFIG}
    # 4. systemd管理kubelet

    cat >/usr/lib/systemd/system/kubelet.service <<EOF
[Unit]
Description=Kubernetes kubelet
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/opt/kubernetes/cfg/kubelet.conf
ExecStart=/opt/kubernetes/bin/kubelet "\$KUBELET_OPTS"
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    # 5. 启动并设置开机启动
    systemctl daemon-reload
    systemctl enable kubelet
    systemctl stop kubectl
    systemctl start kubelet
    systemctl status kubelet
    netstat -lntp

}

install_kube_proxy() {

    # 部署kube-proxy
    cat >/opt/kubernetes/cfg/kube-proxy.conf <<EOF
KUBE_PROXY_OPTS="--logtostderr=false \\
--v=2 \\
--log-dir=/opt/kubernetes/logs \\
--config=/opt/kubernetes/cfg/kube-proxy-config.yml"
EOF

    cat >/opt/kubernetes/cfg/kube-proxy-config.yml <<EOF
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
bindAddress: 0.0.0.0
metricsBindAddress: 0.0.0.0:10249
clientConnection:
  kubeconfig: /opt/kubernetes/cfg/kube-proxy.kubeconfig
hostnameOverride: $(hostname)
clusterCIDR: 10.0.0.0/24
EOF
    # 3. 生成kube-proxy.kubeconfig文件
    # 创建证书请求文件
    cd /opt/kubernetes/ssl
    cat >kube-proxy-csr.json <<EOF
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
      "L": "BeiJing",
      "ST": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF

    # 生成证书
    cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-proxy-csr.json | cfssljson -bare kube-proxy
    # 生成kubeconfig文件：
    KUBE_CONFIG="/opt/kubernetes/cfg/kube-proxy.kubeconfig"
    KUBE_APISERVER="https://$master01:6443"
    kubectl config set-cluster kubernetes \
        --certificate-authority=/opt/kubernetes/ssl/ca.pem \
        --embed-certs=true \
        --server=${KUBE_APISERVER} \
        --kubeconfig=${KUBE_CONFIG}
    kubectl config set-credentials kube-proxy \
        --client-certificate=./kube-proxy.pem \
        --client-key=./kube-proxy-key.pem \
        --embed-certs=true \
        --kubeconfig=${KUBE_CONFIG}
    kubectl config set-context default \
        --cluster=kubernetes \
        --user=kube-proxy \
        --kubeconfig=${KUBE_CONFIG}
    kubectl config use-context default --kubeconfig=${KUBE_CONFIG}
    cat >/usr/lib/systemd/system/kube-proxy.service <<EOF
[Unit]
Description=Kubernetes Proxy
After=network.target

[Service]
EnvironmentFile=/opt/kubernetes/cfg/kube-proxy.conf
ExecStart=/opt/kubernetes/bin/kube-proxy \$KUBE_PROXY_OPTS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl start kube-proxy
    systemctl enable kube-proxy
    systemctl status kube-proxy
    cd $curPath
}
install_kubelet_rbac() {

    # 5.6 授权apiserver访问kubelet
    cat >apiserver-to-kubelet-rbac.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
      - pods/log
    verbs:
      - "*"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF

    kubectl apply -f apiserver-to-kubelet-rbac.yaml

}
