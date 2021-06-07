kubectl create namespace logging
kubectl apply -f elasticsearch-svc.yaml
kubectl apply -f elasticsearch-statefulset.yaml
kubectl port-forward es-0 9200:9200 -n logging &
kubectl apply -f kibana.yaml
kubectl get svc -n logging
kubectl apply -f fluentd-configmap.yaml
# label
kubectl label node k8s-node01 kubernetes.io/fluentd-ds-ready=true
kubectl label node k8s-node02 kubernetes.io/fluentd-ds-ready=true
kubectl apply -f fluentd-daemonset.yaml
kubectl apply -f dummylogs.yaml

kubectl create secret generic smtp-auth --from-file=smtp_auth_file.yaml -n logging
kubectl apply -f elastalert.yaml
