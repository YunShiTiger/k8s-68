# https://www.cnblogs.com/evescn/p/16340453.html

mkdir -p /root/elk/es/certs
cd /root/elk/es/certs
wget https://get.helm.sh/helm-v3.10.0-linux-amd64.tar.gz
tar -zxvf helm-v3.10.0-linux-amd64.tar.gz
mv linux-amd64/helm /usr/bin/
rm -rf linux-amd64/

docker rm -f elastic-charts-certs

# 运行容器生成证书
docker run --name elastic-charts-certs -i -w /app elasticsearch:7.16.3 /bin/sh -c \
  "elasticsearch-certutil ca --out /app/elastic-stack-ca.p12 --pass '' && \
    elasticsearch-certutil cert --ca /app/elastic-stack-ca.p12 --pass '' --ca-pass '' --out /app/elastic-certificates.p12"

# 从容器中将生成的证书拷贝出来
docker cp elastic-charts-certs:/app/elastic-certificates.p12 ./

# 删除容器
docker rm -f elastic-charts-certs

# 将 pcks12 中的信息分离出来，写入文件
openssl pkcs12 -nodes -passin pass:'' -in elastic-certificates.p12 -out elastic-certificate.pem

kubectl delete secret elastic-certificates elastic-certificate-pem elastic-credentials

# 创建 test-middleware 名称空间
kubectl create ns test-middleware

# 添加证书
kubectl -n test-middleware create secret generic elastic-certificates --from-file=elastic-certificates.p12
kubectl -n test-middleware create secret generic elastic-certificate-pem --from-file=elastic-certificate.pem

# 设置集群用户名密码，用户名不建议修改
kubectl -n test-middleware create secret generic elastic-credentials --from-literal=username=elastic --from-literal=password=admin@123
kubectl -n test-middleware get secret

cd /root/elk/es/
# 添加 Chart 仓库
helm repo add elastic https://helm.elastic.co
helm repo update
# 拉取 chart 到本地 /root/elk/es 目录
helm pull elastic/elasticsearch --version 7.16.3
tar -zxvf elasticsearch-7.16.3.tgz
cp elasticsearch/values.yaml ./values-test.yaml

# 安装 ElasticSearch Master 节点
helm -n test-middleware install elasticsearch-master -f es-master-values.yaml --version 7.16.3 elastic/elasticsearch

# 安装 ElasticSearch Data 节点
helm -n test-middleware install elasticsearch-data -f es-data-values.yaml --version 7.16.3 elastic/elasticsearch

# 安装 ElasticSearch Client 节点
helm -n test-middleware install elasticsearch-client -f es-client-values.yaml --version 7.16.3 elastic/elasticsearch

# 安装 kibana 节点
helm -n test-middleware install kibana -f es-kibana-values.yaml --version 7.16.3 elastic/kibana

kubectl get pods --namespace=test-middleware -l app=elasticsearch-master -w
# helm test elasticsearch-master --cleanup

helm uninstall -n test-middleware kibana
helm uninstall -n test-middleware elasticsearch-client
helm uninstall -n test-middleware elasticsearch-data
helm uninstall -n test-middleware elasticsearch-master

#http://k8s-worker-1:30601
#elastic/admin@123
