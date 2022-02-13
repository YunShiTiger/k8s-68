tags: addons, EFK, fluentd, elasticsearch, kibana

# 08-5. 部署 EFK 插件

<!-- TOC -->

- [08-5. 部署 EFK 插件](#08-5-部署-efk-插件)
    - [修改配置文件](#修改配置文件)
    - [执行定义文件](#执行定义文件)
    - [检查执行结果](#检查执行结果)
    - [通过 kubectl proxy 访问 kibana](#通过-kubectl-proxy-访问-kibana)

<!-- /TOC -->

## 修改配置文件


``` bash

# wget https://dl.k8s.io/v1.21.0/kubernetes-server-linux-amd64.tar.gz
# tar -zxf kubernetes-server-linux-amd64.tar.gz
mkdir ./kubernetes
wget https://dl.k8s.io/v1.21.0/kubernetes-src.tar.gz
tar -zxf kubernetes-src.tar.gz -C ./kubernetes
cd kubernetes/cluster/addons/fluentd-elasticsearch
sed -i -e 's_quay.io_quay.mirrors.ustc.edu.cn_' es-statefulset.yaml # 使用中科大的 Registry
sed -i -e 's_quay.io_quay.mirrors.ustc.edu.cn_' fluentd-es-ds.yaml # 使用中科大的 Registry
kubectl apply -f .

kubectl get all -n kube-system |grep -E 'elasticsearch|fluentd|kibana'

kubectl -n kube-system logs -f $(kubectl get pod -n kube-system |grep kibana-logging|awk '{print $1}')
```

注意：只有当 Kibana pod 启动完成后，浏览器才能查看 kibana dashboard，否则会被拒绝。

## 通过 kubectl proxy 访问 kibana

创建代理：

``` bash
kubectl proxy --address='0.0.0.0' --port=8086 --accept-hosts='^*$' &
# Starting to serve on 10.10.10.223:8086
# kubectl patch  -n kube-system  service/kibana-logging -p '{"spec":{"type":"LoadBalancer"}}'
# kubectl patch  -n kube-system  service/kibana-logging -p '{"spec":{"type":"ClusterIP"}}'
```
<!-- kubectl get svc -n kube-system |grep -v TYPE|grep kibana-logging|awk '{print $3}' -->

浏览器访问 URL：`http://10.10.10.223:8086/api/v1/namespaces/kube-system/services/kibana-logging/proxy`

在 Management -> Indices 页面创建一个 index（相当于 mysql 中的一个 database），选中 `Index contains time-based events`，使用默认的 `logstash-*` pattern，点击 `Create` ;

![es-setting](../images/es-setting.png)

创建 Index 后，稍等几分钟就可以在 `Discover` 菜单下看到 ElasticSearch logging 中汇聚的日志；

![es-home](../images/es-home.png)
