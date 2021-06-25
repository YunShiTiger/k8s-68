# rm namespace.yaml* metallb.yaml*
# wget https://raw.githubusercontent.com/metallb/metallb/v0.9.6/manifests/namespace.yaml
# wget https://raw.githubusercontent.com/metallb/metallb/v0.9.6/manifests/metallb.yaml

kubectl delete all --all --force
kubectl delete -f metallb.yaml --force
kubectl delete -f config.yaml --force
kubectl delete -f namespace.yaml --force
kubectl delete secret -n metallb-system memberlist
kubectl delete configmap -n metallb-system config
kubectl delete all --all --force -n metallb-system

kubectl apply -f namespace.yaml
kubectl apply -f metallb.yaml
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

# 如果EXTERNAL-IP 一直pending 查看日志
# kubectl logs -l component=controller -n metallb-system
