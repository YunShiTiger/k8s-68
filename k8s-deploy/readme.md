## 更简单的方法

``````shell
wget -c https://sealyun.oss-cn-beijing.aliyuncs.com/latest/sealos
chmod +x sealos
mv sealos /usr/bin
wget -c https://sealyun.oss-cn-beijing.aliyuncs.com/2fb10b1396f8c6674355fcc14a8cda7c-v1.21.0/kube1.21.0.tar.gz
yum install -y socat
sealos init --passwd 'root' --master 192.168.33.100 --node 192.168.33.101 --node 192.168.33.102 --pkg-url /root/kube1.21.0.tar.gz --version v1.21.0

``````

key证书 -> key 秘钥
crt 秘钥
ca签署证书
