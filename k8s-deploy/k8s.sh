. ./common.sh

install_etcd() {
  # （1）安装 CFSSL
  mkdir -p /opt/etcd/ssl
  cd /opt/etcd/ssl

  # （4）生成CA证书（ca.pem）和密钥（ca-key.pem）ca.csr
  cfssl gencert -initca ca-csr.json | cfssljson -bare ca
  # （5）分发证书
  for node in ${all_nodes[@]}; do
    scp ca.csr ca-key.pem ca.pem ca-csr.json ca-config.json $node:/opt/etcd/ssl
  done
  # （1）准备etcd软件包
  for node in ${etcd_nodes[@]}; do
    ssh $node "rm -rf /var/lib/etcd/*;mkdir -p /opt/etcd/{bin,cfg,log,ssl};"
  done
  set_proxy

  cd /opt/etcd/ssl
  # （2）创建 etcd 证书签名请求
  OPTS=""
  for node in ${etcd_nodes[@]}; do
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
  cfssl gencert -ca=/opt/etcd/ssl/ca.pem -ca-key=/opt/etcd/ssl/ca-key.pem -config=/opt/etcd/ssl/ca-config.json -profile=kubernetes etcd-csr.json | cfssljson -bare etcd

  for node in ${etcd_nodes[@]}; do
    scp etcd*.pem $node:/opt/etcd/ssl
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
ETCD_CERT_FILE="/opt/etcd/ssl/etcd.pem"
ETCD_KEY_FILE="/opt/etcd/ssl/etcd-key.pem"
ETCD_TRUSTED_CA_FILE="/opt/etcd/ssl/ca.pem"
ETCD_PEER_CERT_FILE="/opt/etcd/ssl/etcd.pem"
ETCD_PEER_KEY_FILE="/opt/etcd/ssl/etcd-key.pem"
ETCD_PEER_TRUSTED_CA_FILE="/opt/etcd/ssl/ca.pem"
ETCD_CLIENT_CERT_AUTH="true"
ETCD_PEER_CLIENT_CERT_AUTH="true"

' >/opt/etcd/cfg/etcd.conf

  # （6）创建ETCD系统服务
  echo -e '[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
WorkingDirectory=/var/lib/etcd
EnvironmentFile=-/opt/etcd/cfg/etcd.conf
#User=etcd
# set GOMAXPROCS to number of processors
ExecStart=/bin/bash -c "GOMAXPROCS=$(nproc) /opt/etcd/bin/etcd"
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target' >/etc/systemd/system/etcd.service

  # （7）重新加载系统服务并拷贝etcd.conf和etcd.service文件到其他节点
  for node in ${etcd_nodes[@]}; do
    scp /etc/systemd/system/etcd.service $node:/etc/systemd/system/
    scp /opt/etcd/cfg/etcd.conf $node:/opt/etcd/cfg/etcd.conf
  done

  for node in ${etcd_nodes[@]}; do
    ssh $node "sed -i \"s/HOST_NAME/$node/g\" /opt/etcd/cfg/etcd.conf"
    ip=$(eval echo '$'"$node")
    ssh $node 'sed -i "s/HOSTNAME/'${ip}'/g" /opt/etcd/cfg/etcd.conf'
    ssh $node 'systemctl daemon-reload'
  done
  cd /opt/etcd/bin
  cat >run.sh <<EOF
#!/bin/bash
systemctl start etcd;
systemctl enable etcd;
systemctl status etcd;
EOF
  for node in ${etcd_nodes[@]}; do
    scp run.sh $node:/opt/etcd/bin/run.sh
    ssh $node "chmod +x /opt/etcd/bin/run.sh;"
    ssh -t $node "nohup /opt/etcd/bin/run.sh &"
    ssh $node '/opt/etcd/bin/run.sh 2 2 >/dev/null 2>&1 &'
  done

  sleep 10
  for node in ${etcd_nodes[@]}; do
    ssh $node "netstat -tulnp | grep etcd"
  done
  # （8）验证ETCD集群
  /opt/etcd/bin/etcdctl --endpoints=https://$master01:2379 --ca-file=/opt/etcd/ssl/ca.pem --cert-file=/opt/etcd/ssl/etcd.pem --key-file=/opt/etcd/ssl/etcd-key.pem cluster-health

}

install_k8s_master() {
  cd $curPath
  # 1、签发kube-apiserver HTTPS证书
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
  cat >ca-csr.json <<EOF
{
    "CN": "kubernetes",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Beijing",
            "ST": "Beijing",
            "O": "k8s",
            "OU": "System"
        }
    ]
}
EOF
  for node in ${etcd_nodes[@]}; do
    scp ca* $node:/opt/kubernetes/ssl
  done

  cfssl gencert -initca ca-csr.json | cfssljson -bare ca -
  OPTS=""
  for node in ${all_nodes[@]}; do
    OPTS="$OPTS,\"$(eval echo $(eval echo '$'"$node"))\""
  done
  OPTS=${OPTS:1}
  echo -e '{
    "CN": "etcd",
    "hosts": [
      "127.0.0.1",
      "10.0.0.1",
      '$OPTS',
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
            "ST": "BeiJing",
            "L": "BeiJing",
            "O": "k8s",
            "OU": "System"
        }
    ]
}' >server-csr.json
  # 2、生成证书server-key.pem server.pem
  cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes server-csr.json | cfssljson -bare server

  # for node in ${etcd_nodes[@]}; do
  #   scp server*.pem $node:/opt/kubernetes/ssl
  # done
  ETCDOPTS=""
  for node in ${etcd_nodes[@]}; do
    ETCDOPTS="$ETCDOPTS,https://$(eval echo $(eval echo '$'"$node")):2379"
  done
  ETCDOPTS=${ETCDOPTS:1}
  # 3、部署kube-apiserver
  echo -e 'KUBE_APISERVER_OPTS="--logtostderr=false \\
--v=2 \\
--log-dir=/opt/kubernetes/log \\
--etcd-servers='${ETCDOPTS}' \\
--bind-address='${master01}' \\
--secure-port=6443 \\
--advertise-address='${master01}' \\
--allow-privileged=true \\
--service-cluster-ip-range=10.0.0.0/24 \\
--enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,ResourceQuota,NodeRestriction \\
--authorization-mode=RBAC,Node \\
--enable-bootstrap-token-auth=true \\
--token-auth-file=/opt/kubernetes/cfg/token.csv \\
--service-node-port-range=30000-32767 \\
--kubelet-client-certificate=/opt/kubernetes/ssl/server.pem \\
--kubelet-client-key=/opt/kubernetes/ssl/server-key.pem \\
--tls-cert-file=/opt/kubernetes/ssl/server.pem \\
--tls-private-key-file=/opt/kubernetes/ssl/server-key.pem \\
--client-ca-file=/opt/kubernetes/ssl/ca.pem \\
--service-account-key-file=/opt/kubernetes/ssl/ca-key.pem \\
--service-account-issuer=api \\
--service-account-signing-key-file=/opt/kubernetes/ssl/server-key.pem \\
--etcd-cafile=/opt/etcd/ssl/ca.pem \\
--etcd-certfile=/opt/etcd/ssl/etcd.pem \\
--etcd-keyfile=/opt/etcd/ssl/etcd-key.pem \\
--requestheader-client-ca-file=/opt/kubernetes/ssl/ca.pem \\
--proxy-client-cert-file=/opt/kubernetes/ssl/server.pem \\
--proxy-client-key-file=/opt/kubernetes/ssl/server-key.pem \\
--requestheader-allowed-names=kubernetes \\
--requestheader-extra-headers-prefix=X-Remote-Extra- \\
--requestheader-group-headers=X-Remote-Group \\
--requestheader-username-headers=X-Remote-User \\
--enable-aggregator-routing=true \\
--audit-log-maxage=30 \\
--audit-log-maxbackup=3 \\
--audit-log-maxsize=100 \\
--audit-log-path=/opt/kubernetes/log/k8s-audit.log"' >/opt/kubernetes/cfg/kube-apiserver.conf

  cat >/opt/kubernetes/cfg/token.csv <<EOF
c47ffb939f5ca36231d9e3121a252940,kubelet-bootstrap,10001,"system:node-bootstrapper"
EOF
  cat >/usr/lib/systemd/system/kube-apiserver.service <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/opt/kubernetes/cfg/kube-apiserver.conf
ExecStart=/opt/kubernetes/bin/kube-apiserver \$KUBE_APISERVER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl start kube-apiserver
  systemctl enable kube-apiserver

  # 3、部署kube-controller-manager
  cat >/opt/kubernetes/cfg/kube-controller-manager.conf <<EOF
KUBE_CONTROLLER_MANAGER_OPTS="--logtostderr=false \
--v=2 \
--log-dir=/opt/kubernetes/log \
--leader-elect=true \
--kubeconfig=/opt/kubernetes/cfg/kube-controller-manager.kubeconfig \
--bind-address=127.0.0.1 \
--allocate-node-cidrs=true \
--cluster-cidr=10.244.0.0/16 \
--service-cluster-ip-range=10.0.0.0/24 \
--cluster-signing-cert-file=/opt/kubernetes/ssl/ca.pem \
--cluster-signing-key-file=/opt/kubernetes/ssl/ca-key.pem \
--root-ca-file=/opt/kubernetes/ssl/ca.pem \
--service-account-private-key-file=/opt/kubernetes/ssl/ca-key.pem \
--cluster-signing-duration=87600h0m0s"
EOF
  cd /opt/kubernetes/ssl

  echo -e '{
    "CN": "system:kube-controller-manager",
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
            "O": "system:masters",
            "OU": "System"
        }
    ]
}
' >kube-controller-manager-csr.json

  cfssl gencert -ca=/opt/kubernetes/ssl/ca.pem -ca-key=/opt/kubernetes/ssl/ca-key.pem -config=/opt/kubernetes/ssl/ca-config.json -profile=kubernetes kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager
  KUBE_CONFIG="/opt/kubernetes/cfg/kube-controller-manager.kubeconfig"
  KUBE_APISERVER="https://${master01}:6443"

  kubectl config set-cluster kubernetes \
    --certificate-authority=/opt/kubernetes/ssl/ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=${KUBE_CONFIG}
  kubectl config set-credentials kube-controller-manager \
    --client-certificate=./kube-controller-manager.pem \
    --client-key=./kube-controller-manager-key.pem \
    --embed-certs=true \
    --kubeconfig=${KUBE_CONFIG}
  kubectl config set-context default --cluster=kubernetes --user=kube-controller-manager --kubeconfig=${KUBE_CONFIG}
  kubectl config use-context default --kubeconfig=${KUBE_CONFIG}

  cat >/usr/lib/systemd/system/kube-controller-manager.service <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/opt/kubernetes/cfg/kube-controller-manager.conf
ExecStart=/opt/kubernetes/bin/kube-controller-manager \$KUBE_CONTROLLER_MANAGER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl start kube-controller-manager
  systemctl enable kube-controller-manager

  # 部署kube-scheduler
  cat >/opt/kubernetes/cfg/kube-scheduler.conf <<EOF
KUBE_SCHEDULER_OPTS="--logtostderr=false \
--v=2 \
--log-dir=/opt/kubernetes/logs \
--leader-elect \
--kubeconfig=/opt/kubernetes/cfg/kube-scheduler.kubeconfig \
--bind-address=127.0.0.1"
EOF
  cat >kube-scheduler-csr.json <<EOF
{
  "CN": "system:kube-scheduler",
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
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
EOF
  cfssl gencert -ca=/opt/kubernetes/ssl/ca.pem -ca-key=/opt/kubernetes/ssl/ca-key.pem -config=/opt/kubernetes/ssl/ca-config.json -profile=kubernetes kube-scheduler-csr.json | cfssljson -bare kube-scheduler
  KUBE_CONFIG="/opt/kubernetes/cfg/kube-scheduler.kubeconfig"
  KUBE_APISERVER="https://$master01:6443"

  kubectl config set-cluster kubernetes \
    --certificate-authority=/opt/kubernetes/ssl/ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=${KUBE_CONFIG}
  kubectl config set-credentials kube-scheduler \
    --client-certificate=./kube-scheduler.pem \
    --client-key=./kube-scheduler-key.pem \
    --embed-certs=true \
    --kubeconfig=${KUBE_CONFIG}
  kubectl config set-context default \
    --cluster=kubernetes \
    --user=kube-scheduler \
    --kubeconfig=${KUBE_CONFIG}
  kubectl config use-context default --kubeconfig=${KUBE_CONFIG}
  cat >/usr/lib/systemd/system/kube-scheduler.service <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/opt/kubernetes/cfg/kube-scheduler.conf
ExecStart=/opt/kubernetes/bin/kube-scheduler \$KUBE_SCHEDULER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl start kube-scheduler
  systemctl enable kube-scheduler

  # 5. 查看集群状态
  cat >admin-csr.json <<EOF
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
      "L": "BeiJing",
      "ST": "BeiJing",
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
EOF
  cfssl gencert -ca=/opt/kubernetes/ssl/ca.pem -ca-key=/opt/kubernetes/ssl/ca-key.pem -config=/opt/kubernetes/ssl/ca-config.json -profile=kubernetes admin-csr.json | cfssljson -bare admin
  rm -rf /root/.kube
  mkdir /root/.kube
  KUBE_CONFIG="/root/.kube/config"
  KUBE_APISERVER="https://$master01:6443"

  kubectl config set-cluster kubernetes \
    --certificate-authority=/opt/kubernetes/ssl/ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=${KUBE_CONFIG}
  kubectl config set-credentials cluster-admin \
    --client-certificate=/opt/kubernetes/ssl/admin.pem \
    --client-key=/opt/kubernetes/ssl/admin-key.pem \
    --embed-certs=true \
    --kubeconfig=${KUBE_CONFIG}
  kubectl config set-context default \
    --cluster=kubernetes \
    --user=cluster-admin \
    --kubeconfig=${KUBE_CONFIG}
  kubectl config use-context default --kubeconfig=${KUBE_CONFIG}
  #ComponentStatus
  kubectl get cs
  # 授权kubelet-bootstrap用户允许请求证书
  kubectl create clusterrolebinding kubelet-bootstrap \
    --clusterrole=system:node-bootstrapper \
    --user=kubelet-bootstrap
  cd $curPath

}

IsContains $(hostname) ${all_nodes}
if [ $inArray == 1 ]; then
  for node in ${all_nodes[@]}; do
    scp $curPath/common.sh $node:$curPath/common.sh
    ssh $node "mkdir -p /opt/etcd;chmod +x $curPath/common.sh;"
    ssh $node ". /$curPath/common.sh;init;install_docker;"
  done
fi

IsContains $(hostname) ${master_nodes}
if [[ $(hostname) =~ ^master01* ]]; then
  install_software
  install_etcd
  install_k8s_master
else
  echo 'over'
fi

for node in ${all_nodes[@]}; do
  ssh $node "cd $curPath;. $curPath/common.sh;install_k8s_worker"
done
# 5.3 批准kubelet证书申请并加入集群
# 查看kubelet证书请求
kubectl get csr
# NAME AGE SIGNERNAME REQUESTOR CONDITION
# node-csr-uCEGPOIiDdlLODKts8J658HrFq9CZ--K6M4G7bjhk8A 6m3s kubernetes.io/kube-apiserver-client-kubelet kubelet-bootstrap Pending

NAME=$(kubectl get csr | grep -v SIGNERNAME | awk '{print $1}')
# 批准申请
kubectl certificate approve $NAME

# 查看节点
kubectl get node
# NAME STATUS ROLES AGE VERSION
# k8s-master1 NotReady v1.18.3 <none >7s
mount | grep kubelet | awk '{print $3}' | xargs umount
kubectl apply -f calico.yaml
# kubectl apply -f kube-flannel.yml
kubectl get pods -n kube-system
kubectl get node
# NAME           STATUS   ROLES    AGE   VERSION
# k8s-master01   Ready    <none>   31m   v1.20.0
# 提前把image文件备好
sleep 10
install_kube_proxy
install_kubelet_rbac

for node in ${all_nodes[@]}; do
  ssh $node "rm -f /opt/kubernetes/cfg/kubelet.kubeconfig;rm -f /opt/kubernetes/ssl/kubelet*"
  scp -r /usr/lib/systemd/system/{kubelet,kube-proxy}.service $node:/usr/lib/systemd/system
done

xxxxxx() {
  wget https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/namespace.yaml

  wget https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.3/aio/deploy/recommended.yaml
  kubectl apply -f recommended.yaml

  kubectl create serviceaccount dashboard-admin -n kube-system
  kubectl create clusterrolebinding dashboard-admin --clusterrole=cluster-admin --serviceaccount=kube-system:dashboard-admin
  kubectl describe secrets -n kube-system $(kubectl -n kube-system get secret | awk '/dashboard-admin/{print $1}')
  kubectl get nodes

  kubectl apply -f https://kuboard.cn/install-script/kuboard.yaml
  kubectl get pods
  kubectl get pods --watch
  kubectl get pods
  kubectl apply -f https://kuboard.cn/install-script/kuboard.yaml
  kubectl get pods -A
  echo $(kubectl -n kube-system get secret $(kubectl -n kube-system get secret | grep kuboard-user | awk '{print $1}') -o go-template='{{.data.token}}' | base64 -d)
  kubectl delete -f https://kuboard.cn/install-script/kuboard.yaml
  kubectl get pods
  kubectl get pods -A
  docker run -d --restart=unless-stopped --name=kuboard -p 80:80/tcp -p 10081:10081/udp -p 10081:10081/tcp -e KUBOARD_ENDPOINT="http://内网IP:80" -e KUBOARD_AGENT_SERVER_UDP_PORT="10081" -e KUBOARD_AGENT_SERVER_TCP_PORT="10081" -v /root/kuboard-data:/data eipwork/kuboard:v3
  docker run -d --restart=unless-stopped --name=kuboard -p 80:80/tcp -p 10081:10081/udp -p 10081:10081/tcp -e KUBOARD_ENDPOINT="http://10.10.10.225:80" -e KUBOARD_AGENT_SERVER_UDP_PORT="10081" -e KUBOARD_AGENT_SERVER_TCP_PORT="10081" -v /root/kuboard-data:/data eipwork/kuboard:v3
  curl -k 'http://10.10.10.225:80/kuboard-api/cluster/liexingK8S/kind/KubernetesCluster/liexingK8S/resource/installAgentToKubernetes?token=BpLnfgDsc2WD8F2qNfHK5a84jjJkwzDk' >kuboard-agent.yaml
  kubectl apply -f ./kuboard-agent.yaml
  kubectl get pods -n kuboard -o wide -l "k8s.kuboard.cn/name in (kuboard-agent, kuboard-agent-2)"
  kubectl describe pods -n kuboard kuboard-agent-55d579d688-25nlz
  kubectl get pods -n kuboard -o wide -l "k8s.kuboard.cn/name in (kuboard-agent, kuboard-agent-2)"

}
