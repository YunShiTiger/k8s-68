# rm -rf k8s-prometheus-adapter
kubectl delete all --all -n prom --force
kubectl apply -f namespace.yaml
kubectl apply -f node_exporter/
kubectl apply -f prometheus/
kubectl apply -f kube-state-metrics/

kubectl get pods -o wide -n prom -w
cd /etc/kubernetes/pki
umask 077
openssl genrsa -out serving.key 2048
openssl req -new -key serving.key -out serving.csr -subj "/CN=serving"
openssl x509 -req -in serving.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out serving.crt -days 36500
kubectl create secret generic cm-adapter-serving-certs --from-file=serving.crt=./serving.crt --from-file=serving.key -n prom
kubectl get secret -n prom
cd -
kubectl apply -f k8s-prometheus-adapter/
kubectl get pods -n prom -w
kubectl api-versions | grep custom
kubectl get svc -n prom
kubectl apply -f podinfo/
kubectl apply -f grafana.yaml
kubectl get all -o wide -n prom
# gcr.io/google_containers  ------>   mirrorgooglecontainers
# http://prometheus.prom.svc:9090
# https://grafana.com/grafana/dashboards/11802
