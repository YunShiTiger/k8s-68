. ./common.sh

install_ca() {
  # （1）安装 CFSSL
  cd ~
  # wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 &&
  #   wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 &&
  #   wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
  if [ -f "cfssl-certinfo_linux-amd64" ]; then
    echo "cfssl-certinfo_linux-amd64 exist"
  else
    wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
  fi
  if [ -f "cfssljson_linux-amd64" ]; then
    echo "cfssljson_linux-amd64  exist"
  else
    wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
  fi
  if [ -f "cfssl_linux-amd64" ]; then
    echo "cfssl_linux-amd64 exist"
  else
    wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
  fi

  rm -rf /usr/local/bin/cfssl*
  cp cfssl-certinfo_linux-amd64 /usr/local/bin/cfssl-certinfo
  cp cfssljson_linux-amd64 /usr/local/bin/cfssljson
  cp cfssl_linux-amd64 /usr/local/bin/cfssl

  chmod +x /usr/local/bin/cfssl*
  for node in ${all_nodes[@]}; do
    scp /usr/local/bin/cfssl* $node:/usr/local/bin
  done
  # （2）创建用来生成 CA 文件的 JSON 配置文件
  cd /opt/kubernetes/ssl
  cat >ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "kubernetes": {
         "expiry": "87600h",
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
  # （3）创建用来生成 CA 证书签名请求（CSR）的 JSON 配置文件
  cat >ca-csr.json <<EOF
{
    "CN": "etcd CA",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Beijing",
            "ST": "Beijing"
        }
    ]
}
EOF
  # （4）生成CA证书（ca.pem）和密钥（ca-key.pem）ca.csr
  cfssl gencert -initca ca-csr.json | cfssljson -bare ca
  # （5）分发证书
  for node in ${all_nodes[@]}; do
    scp ca.csr ca-key.pem ca.pem ca-config.json $node:/opt/kubernetes/ssl
  done
}

install_etcd() {
  # （1）准备etcd软件包
  for node in ${all_nodes[@]}; do
    ssh $node "rm -rf /var/lib/etcd/*;mkdir -p /usr/local/k8s-src;"
  done
  cd /usr/local/k8s-src
  set_proxy
  wget https://github.com/coreos/etcd/releases/download/v3.3.11/etcd-v3.3.11-linux-amd64.tar.gz
  unset_proxy
  tar zxf etcd-v3.3.11-linux-amd64.tar.gz
  cd etcd-v3.3.11-linux-amd64
  cp etcd etcdctl /opt/kubernetes/bin/
  for node in ${all_nodes[@]}; do
    scp etcd etcdctl $node:/opt/kubernetes/bin/
  done

  cd /opt/kubernetes/ssl
  # （2）创建 etcd 证书签名请求
  OPTS=""
  for node in ${all_nodes[@]}; do
    OPTS="$OPTS,\"$(eval echo $(eval echo '$'"$node"))\""
  done
  OPTS=${OPTS:1}
  echo -e '{
    "CN": "etcd",
    "hosts": [
      '$OPTS'
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "ST": "BeiJing",
            "L": "BeiJing",
            "O": "k8s",
            "OU": "System"
        }
    ]
}' >etcd-csr.json
  # （3）生成 etcd 证书和私钥
  cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes etcd-csr.json | cfssljson -bare etcd

  for node in ${etcd_nodes[@]}; do
    scp etcd*.pem $node:/opt/kubernetes/ssl
  done
  # （5）配置ETCD配置文件
  OPTS=""
  for node in ${etcd_nodes[@]}; do
    OPTS="$OPTS,etcd-$node"=https://$(eval echo $(eval echo '$'"$node")):2380
  done
  OPTS=${OPTS:1}
  echo -e '#[Member]
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_PEER_URLS="https://HOSTNAME:2380"
ETCD_LISTEN_CLIENT_URLS="https://HOSTNAME:2379"
ETCD_NAME="etcd-HOST_NAME"
#[Clustering]
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://HOSTNAME:2380"
ETCD_ADVERTISE_CLIENT_URLS="https://HOSTNAME:2379"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER="'${OPTS}'"
ETCD_STRICT_RECONFIG_CHECK="true"
#[Security]
ETCD_CERT_FILE="/opt/kubernetes/ssl/etcd.pem"
ETCD_KEY_FILE="/opt/kubernetes/ssl/etcd-key.pem"
ETCD_TRUSTED_CA_FILE="/opt/kubernetes/ssl/ca.pem"
ETCD_PEER_CERT_FILE="/opt/kubernetes/ssl/etcd.pem"
ETCD_PEER_KEY_FILE="/opt/kubernetes/ssl/etcd-key.pem"
ETCD_PEER_TRUSTED_CA_FILE="/opt/kubernetes/ssl/ca.pem"
ETCD_CLIENT_CERT_AUTH="true"
ETCD_PEER_CLIENT_CERT_AUTH="true"

' >/opt/kubernetes/cfg/etcd.conf

  # （6）创建ETCD系统服务
  echo -e '[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
WorkingDirectory=/var/lib/etcd
EnvironmentFile=-/opt/kubernetes/cfg/etcd.conf
#User=etcd
# set GOMAXPROCS to number of processors
ExecStart=/bin/bash -c "GOMAXPROCS=$(nproc) /opt/kubernetes/bin/etcd"
# Restart=on-failure
# LimitNOFILE=65536

[Install]
WantedBy=multi-user.target' >/etc/systemd/system/etcd.service

  # （7）重新加载系统服务并拷贝etcd.conf和etcd.service文件到其他节点
  for node in ${etcd_nodes[@]}; do
    scp /etc/systemd/system/etcd.service $node:/etc/systemd/system/
    scp /opt/kubernetes/cfg/etcd.conf $node:/opt/kubernetes/cfg/etcd.conf
  done

  for node in ${etcd_nodes[@]}; do
    ssh $node "sed -i \"s/HOST_NAME/$node/g\" /opt/kubernetes/cfg/etcd.conf"
    ip=$(eval echo '$'"$node")
    ssh $node 'sed -i "s/HOSTNAME/'${ip}'/g" /opt/kubernetes/cfg/etcd.conf'
    ssh $node 'systemctl daemon-reload'
  done

  cat >run.sh <<EOF
#!/bin/bash
systemctl start etcd;
ystemctl enable etcd;
systemctl status etcd;
EOF
  for node in ${etcd_nodes[@]}; do
    scp run.sh $node:/opt/kubernetes/run.sh
    ssh $node "chmod +x /opt/kubernetes/run.sh;"
    ssh -t $node "nohup /opt/kubernetes/run.sh &"
    ssh $node '/opt/kubernetes/run.sh 2 2 >/dev/null 2>&1 &'
  done

  sleep 10
  for node in ${etcd_nodes[@]}; do
    ssh $node "netstat -tulnp | grep etcd"
  done
  # （8）验证ETCD集群
  etcdctl --endpoints=https://$master01:2379 --ca-file=/opt/kubernetes/ssl/ca.pem --cert-file=/opt/kubernetes/ssl/etcd.pem --key-file=/opt/kubernetes/ssl/etcd-key.pem cluster-health

}

IsContains $(hostname) ${all_nodes}
if [ $inArray == 1 ]; then
  for node in ${etcd_nodes[@]}; do
    scp common.sh $node:/opt/kubernetes/common.sh
    ssh $node "mkdir -p /opt/kubernetes;chmod +x /opt/kubernetes/common.sh;"
    ssh $node ". /opt/kubernetes/common.sh;init;install_docker;"
  done
fi

IsContains $(hostname) ${master_nodes}
if [[ $(hostname) =~ ^master01* ]]; then
  install_ca
  install_etcd
else
  echo 'over'
fi
