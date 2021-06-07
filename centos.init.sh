init() {
    mv /etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel.repo.bak
    mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup
    wget -O /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
    wget -O /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo
    # 非阿里云ECS用户会出现 Couldn't resolve host 'mirrors.cloud.aliyuncs.com' 信息，不影响使用，可以修改配置
    sed -i -e '/mirrors.cloud.aliyuncs.com/d' -e '/mirrors.aliyuncs.com/d' /etc/yum.repos.d/CentOS-Base.repo

}

install_docker() {
    echo -e '[kubernetes]
name=Kubernetes Repo
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
enabled=1
' >/etc/yum.repos.d/kubernetes.repo

    wget https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg

    rpm --import rpm-package-key.gpg
    yum repolist
    yum clean all
    yum makecache
    yum install -y epel-release
    yum install golang git docker-ce kubectl kubeadm kubelet -y
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
