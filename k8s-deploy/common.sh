master01='192.168.33.100'
node01='192.168.33.101'
node02='192.168.33.102'
node03='192.168.33.103'
master_nodes=(master01)
all_nodes=(master01 node01 node02 node03)
etcd_nodes=(master01 node01 node02)

k8s_version='v1.20.6'

inArray=0

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
    ps -ef | grep ssh | grep install_docker | awk '{print $2}' | xargs kill -9
    ps -ef | grep -v 'grep' | grep etcd | awk '{print $2}' | xargs kill -9
    ps -ef | grep -v 'grep' | grep etcd
    sed -i 's/enforcing/disabled/' /etc/selinux/config
    setenforce 0
    swapoff -a
    sed -ri 's/.*swap.*/#&/' /etc/fstab
    pkill -9 etcd
    yum install ntpdate -y
    ntpdate ntp1.aliyun.com

    rm -rf /usr/local/k8s-src
    rm -rf /opt/kubernetes/*
    rm -rf /usr/local/k8s-src/ssl
    rm -rf /var/lib/etcd/*
    rm -rf /etc/systemd/system/etcd.service
    mkdir -p /opt/kubernetes/{cfg,bin,ssl,log}
    mkdir -p /usr/local/k8s-src/ssl
    mkdir -p /var/lib/etcd/
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
    # rpm --import rpm-package-key.gpg
    wget -O /etc/yum.repos.d/docker-ce.repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

    yum repolist
    yum clean all
    yum makecache
    # yum install -y epel-release
    yum install docker-ce docker-ce-cli containerd.io golang git kubectl kubeadm kubelet -y
    systemctl start docker
    systemctl enable docker
    systemctl status docker
}

install_python39() {

    yum install automake build-essential git zlib* openssl* libffi* libssl* libsqlite3* -y
    wget https://www.python.org/ftp/python/3.9.2/Python-3.9.2.tgz
    tar -zxvf Python-3.9.2.tgz
    cd Python-3.9.2
    ./configure --with-ssl && make -j 16 && make install
    cd ..
    rm -rf ./Python-3.9.2*
}

set_proxy() {
    # export http_proxy=http://10.10.10.20:1081
    # export http_proxy=https://10.10.10.20:1081
    # export http_proxy=http://10.10.16.89:1087
    # export https_proxy=https://10.10.16.89:1087
    export http_proxy=http://192.168.0.104:8080
    export https_proxy=https://192.168.0.104:8080

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
