yum install bash-completion -y
source /usr/share/bash-completion/bash_completion

# key 私钥
# csr 签名申请
# crt  证书

# 私钥 (可以用来解密、签名)
# 公开的：公钥 证书(用私钥签名,经过CA认证的公钥;可以用来加密、验签)
# 客户端拿着证书加密，服务端拿着私钥解密
# 服务端会在建立连接后将证书发往客户端
# 要达到数据安全传输的目的，必须发送方和接收方都持有对方的公钥和自己私钥；
# 为保证自己所持有的的对方的公钥不被篡改，需要CA机构对其进行验证,即用ca的公钥解密证书;解密成功也就拿到了原始的公钥

cd /etc/kubernetes/pki/
# -------可以使用域名访问myapp.magedu.com--------------
# dashboard.key 私钥
(
    umask 077
    openssl genrsa -out dashboard.key 2048
)

#magedu.crt 证书申请
openssl req -new -key dashboard.key -out dashboard.csr -subj "/O=magedu/CN=myapp.magedu.com"
#对证书进行签名
openssl x509 -req -in dashboard.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out dashboard.crt -days 36500
openssl x509 -in dashboard.crt -text -noout # 查看证书信息
kubectl create ns kubernetes-dashboard
kubectl create secret generic kubernetes-dashboard-certs --from-file=magedu.crt --from-file=dashboard.key -n kubernetes-dashboard
#----------------------------------

kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.3.1/aio/deploy/recommended.yaml
# 去登录dashboard需要sa账号
# data.token 可以直接拿来登录
kubectl create serviceaccount dashboard-admin -n kubernetes-dashboard
kubectl create clusterrolebinding dashboard-cluster-admin --clusterrole=cluster-admin --serviceaccount=kubernetes-dashboard:dashboard-admin
DASHBOARD_LOGIN_TOKEN=$(kubectl get secret $(kubectl get secret -n kubernetes-dashboard | grep dashboard-admin-token | awk '{print $1}') -ogo-template --template='{{.data.token}}' | base64 --decode)
echo ${DASHBOARD_LOGIN_TOKEN}

kubectl config set-cluster mykubernets --certificate-authority=./ca.crt --server="https://192.168.33.100:6443" -embed-certs=true --kubeconfig=/root/admin.conf
kubectl config set-credentials dashboard-admin-tag --token=$DASHBOARD_LOGIN_TOKEN --kubeconfig=/root/admin.conf
kubectl config set-context dashboard-admin-tag@mykubernets --cluster=mykubernets --user=dashboard-admin-tag --kubeconfig=/root/admin.conf
kubectl config use-context dashboard-admin-tag@mykubernets --kubeconfig=/root/admin.conf
