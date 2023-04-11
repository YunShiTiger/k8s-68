# 需要提前部署好 pvc provisioner



cat > values.yaml  <<EOF
etcd:
  image: registry.k8s.io/etcd:3.5.6-0
controller:
  image: registry.k8s.io/kube-controller-manager:v1.26.2
scheduler:
  image: registry.k8s.io/kube-scheduler:v1.26.2
api:
  image: registry.k8s.io/kube-apiserver:v1.26.2
EOF


vcluster create vcluster --distro k8s -n vcluster -f values.yaml

kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: vcluster-nodeport
  namespace: vcluster
spec:
  selector:
    app: vcluster
    release: vcluster
  ports:
    - name: https
      port: 443
      targetPort: 8443
      protocol: TCP
      nodePort: 32000
  type: NodePort
EOF



kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: demo
---
kind: Pod
apiVersion: v1
metadata:
  name: test-pod
  namespace: demo
spec:
  containers:
    - name: test-pod
      image: centos:7
      command:
        - sleep
        - "36000"
EOF
