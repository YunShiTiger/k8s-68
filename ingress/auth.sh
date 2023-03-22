# htpasswd是apache httpd工具包中的工具
# 安装htpasswd
## centos
yum install httpd-tools -y
## ubuntu
apt install apache2-utils -y
# 创建认证文件 QAZwsx@123..   输入密码
htpasswd -c auth admin
# 查看文件内容
cat auth

# -n ingress-nginx
kubectl delete secret basic-auth
kubectl create secret generic basic-auth --from-file=auth





# kubectl patch  -n ingress-nginx  service/kibana-logging -p '{"spec":{"type":"ClusterIP"}}'
# kubectl -n ingress-nginx port-forward ingress-nginx-controller 80:80


cat >/etc/systemd/system/ingress-nginx.service <<EOF
[Unit]
Description=ingress-nginx
After=multi-user.target

[Service]
LimitNOFILE=204800
User=root
Group=root
WorkingDirectory=/root
ExecStart=/usr/bin/kubectl -n ingress-nginx port-forward service/ingress-nginx-controller --address 0.0.0.0 80:80
PIDFile=/var/run/bas.pid
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ingress-nginx.service
sudo systemctl start ingress-nginx.service
sudo systemctl status ingress-nginx.service
