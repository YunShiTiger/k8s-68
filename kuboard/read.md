https://www.kuboard.cn/install/install-dashboard.html#%E5%AE%89%E8%A3%85


kubectl apply -f https://kuboard.cn/install-script/kuboard.yaml

kubectl apply -f https://addons.kuboard.cn/metrics-server/0.3.7/metrics-server.yaml

kubectl get pods -l k8s.kuboard.cn/name=kuboard -n kube-system

echo $(kubectl -n kube-system get secret $(kubectl -n kube-system get secret | grep ^kuboard-user | awk '{print $1}') -o go-template='{{.data.token}}' | base64 -d)
