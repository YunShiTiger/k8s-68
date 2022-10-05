mkdir ingress && cd ingress
# 新建仓库
# 集群版本是1.19.4
kubectl create ns ingress-nginx
# curl -k -o deploy.yaml https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v0.47.0/deploy/static/provider/cloud/deploy.yaml
# sed -i 's/k8s.gcr.io\/ingress-nginx\//docker.io\/acejilam\/ingress-nginx-/g' deploy.yaml
# sed -i 's/LoadBalancer/NodePort/g' deploy.yaml
# sed -i 's/@sha256:52f0058bed0a17ab0fb35628ba97e8d52b5d32299fbc03cc0f6c7b9ff036b61a//g' deploy.yaml

kubectl label node k8s-master-1 type-
kubectl label node k8s-master-2 type-
kubectl label node k8s-master-3 type-
kubectl label node k8s-master-1 type="ingress"
kubectl label node k8s-master-2 type="ingress"
kubectl label node k8s-master-3 type="ingress"

kubectl apply -f deploy.yaml -n ingress-nginx


# acejilam/ingress-nginx-controller:v0.46.0

kubectl delete -f . -n ingress-nginx
