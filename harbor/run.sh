# kubectl patch storageclass rook-ceph-block -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

kubectl create namespace harbor

# 获得证书
openssl req -newkey rsa:4096 -nodes -sha256 -keyout ca.key -x509 -days 3650 -out ca.crt -subj "/C=CN/CN=ca.com"

# 生成证书签名请求
openssl req -newkey rsa:4096 -nodes -sha256 -keyout tls.key -out tls.csr -subj "/C=CN/CN=harbor.k8s.com"

# 生成证书
openssl x509 -req -days 3650 -in tls.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out tls.crt

kubectl -n harbor delete secret hub-7d-tls
kubectl -n harbor create secret generic hub-7d-tls --from-file=tls.crt --from-file=tls.key --from-file=ca.crt
kubectl -n harbor get secret hub-7d-tls

helm repo add harbor https://helm.goharbor.io
helm install harbor harbor/harbor --version 1.4.2 -f 1、values.yaml -n harbor

kubectl get deployment -n harbor

# 需要将域名的 DNS 指向任意 master 服务器地址
echo '192.168.10.101 harbor.k8s.com' >>/etc/hosts


#  Harobr主页->配置管理->系统配置->镜像库根证书

mkdir -p /etc/docker/certs.d/harbor.k8s.com
cd /etc/docker/certs.d/harbor.k8s.com
curl -k -o ca.crt https://harbor.k8s.com/api/v2.0/systeminfo/getcert
docker login -u admin -p admin@123 harbor.k8s.com
# helm -n harbor uninstall harbor
