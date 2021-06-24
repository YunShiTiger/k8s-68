yum install bash-completion -y
source /usr/share/bash-completion/bash_completion
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.3.1/aio/deploy/recommended.yaml
# 去登录dashboard需要sa账号
cd /etc/kubernetes/pki/
# dashboard.key
(
    umask 077
    openssl genrsa -out dashboard.key 2048
)
#dashboard.crt
openssl req -new -key dashboard.key -out dashboard.crt -subj "/O=magedu/CN=myapp.magedu.com"
#对证书进行签名
openssl x509 -req -in dashboard.crt -CA ca.crt -CAkey ca.key -CAcreateserial -out dashboard.crt -days 36500
kubectl create secret generic dashboard-secret --from-file=dashboard.crt --from-file=dashboard.key -n kubernetes-dashboard
kubectl create serviceaccount dashboard-admin -n kubernetes-dashboard
kubectl create clusterrolebinding dashboard-cluster-admin --clusterrole=cluster-admin --serviceaccount=kubernetes-dashboard:dashboard-admin
kubectl config set-cluster mykubernets --certificate-authority=./ca.crt --server="https://192.168.33.100:6443" -embed-certs=true --kubeconfig=/root/admin.conf
# data.token 可以直接拿来登录
token=$(kubectl get secret $(kubectl get secret -n kubernetes-dashboard | grep dashboard-admin-token | awk '{print $1}') -ogo-template --template='{{.data.token}}' | base64 --decode)
kubectl config set-credentials dashboard-admin-tag --token=$token --kubeconfig=/root/admin.conf
kubectl config set-context dashboard-admin-tag@mykubernets --cluster=mykubernets --user=dashboard-admin --kubeconfig=/root/admin.conf
kubectl config use-context dashboard-admin-tag@mykubernets --kubeconfig=/root/admin.conf
