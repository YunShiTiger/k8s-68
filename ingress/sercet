#1、做证书
openssl genrsa -out tls.key 2048
#2、制作自签证书
openssl req -new -x509 -key tls.key -out tls.crt -subj /C=CN/ST=Beijing/L=Beijing/O=Devops/CN=myapp.magedu.com
#3、crt格式转换
kubectl create secret tls nginx-ingress-secret --cert=tls.crt --key=tls.key
# kubectl get secret
# kubectl describe secret nginx-ingress-secret
