tags: addons, kube-prometheus, prometheus, grafana

# 08-4. 部署 kube-prometheus 插架
kube-prometheus 是一整套监控解决方案，它使用 Prometheus 采集集群指标，Grafana 做展示，包含如下组件：
+ The Prometheus Operator
+ Highly available Prometheus
+ Highly available Alertmanager
+ Prometheus node-exporter
+ Prometheus Adapter for Kubernetes Metrics APIs （k8s-prometheus-adapter）
+ kube-state-metrics
+ Grafana

其中 k8s-prometheus-adapter 使用 Prometheus 实现了 metrics.k8s.io 和 custom.metrics.k8s.io API，所以**不需要再部署** `metrics-server`。


## 下载和安装

``` bash
git clone https://github.com/coreos/kube-prometheus.git
cd kube-prometheus/
# 使用科大的 Registry
sed -i -e 's_quay.io_quay.mirrors.ustc.edu.cn_' manifests/*.yaml manifests/setup/*.yaml
sed -i -e 's_k8s.gcr.io/kube-state-metrics/kube-state-metrics:_acejilam/kube-state-metrics:_' manifests/*.yaml manifests/setup/*.yaml
kubectl apply -f manifests/setup # 安装 prometheus-operator
kubectl apply -f manifests/ # 安装 promethes metric adapter
```

## 查看运行状态

``` bash
kubectl get pods -n monitoring
kubectl top pods -n monitoring
kubectl port-forward --address 0.0.0.0 pod/prometheus-k8s-0 -n monitoring 9090:9090
```
+ port-forward 依赖 socat。

浏览器访问：http://127.0.0.1:9090/graph?g0.expr=instance%3Anode_cpu%3Aratio&g0.tab=0&g0.stacked=0&g0.show_exemplars=0&g0.range_input=1h

## 访问 Grafana UI

启动代理：

``` bash
$ kubectl port-forward --address 0.0.0.0 svc/grafana -n monitoring 3000:3000
Forwarding from 0.0.0.0:3000 -> 3000
```

然后，就可以看到各种预定义的 dashboard 了：


https://grafana.com/grafana/dashboards?search=kubernetes
8588
13105
