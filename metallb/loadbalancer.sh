rm namespace.yaml* metallb.yaml* kube-flannel*
wget https://raw.githubusercontent.com/metallb/metallb/v0.10.2/manifests/namespace.yaml
wget https://raw.githubusercontent.com/metallb/metallb/v0.10.2/manifests/metallb.yaml
wget https://github.com/coreos/flannel/raw/master/Documentation/kube-flannel.yml
# kubectl delete -f metallb.yaml --force
# kubectl delete -f config.yaml --force
# kubectl delete -f namespace.yaml --force
# kubectl delete secret -n metallb-system memberlist
# kubectl delete configmap -n metallb-system config
# kubectl delete all --all --force -n metallb-system

kubectl apply -f namespace.yaml
kubectl apply -f metallb.yaml
kubectl apply -f kube-flannel.yml
kubectl get configmap kube-proxy -n kube-system -o yaml |
  sed -e "s/strictARP: false/strictARP: true/" |
  kubectl apply -f - -n kube-system
# On first install only

kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 192.168.33.100-192.168.33.102
EOF

kubectl get all -o wide -n metallb-system
# 等待所有pod running
# 如果EXTERNAL-IP 一直pending 查看日志
# kubectl logs -f -l component=controller -n metallb-system
# kubectl apply -f app.yaml
