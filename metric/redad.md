wget https://github.com/kubernetes-sigs/metrics-server/archive/v0.3.6.tar.gz
tar -zxvf v0.3.6.tar.gz
mv ./metrics-server-0.3.6/deploy/1.8+/* .


修改了一些问题，注意yaml
https://www.cnblogs.com/binghe001/p/12821804.html


image: registry.cn-hangzhou.aliyuncs.com/google_containers/etrics-server-amd64:v0.3.6
image: registry.cn-hangzhou.aliyuncs.com/google_containers/addon-resizer:1.8.11

kubectl proxy --port 8000
curl http://127.0.0.1:8000/apis/metrics.k8s.io/v1beta1
curl http://127.0.0.1:8000/apis/metrics.k8s.io/v1beta1/nodes

等一会metric-resolution 周期10秒
kubectl top nodes

kubectl apply -f "https://cloud.weave.works/k8s/scope.yaml?k8s-version=$(kubectl version | base64 | tr -d '\n')"
