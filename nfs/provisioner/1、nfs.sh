# https://mp.weixin.qq.com/s/xKPAHWuLBMYuaVzpel5rUQ
# store1
yum install -y nfs-utils rpcbind
rm -rf /nfs
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config

mkdir -p /nfs
chown -R nfsnobody:nfsnobody /nfs
echo '/nfs   192.168.0.0/16(rw,async,no_root_squash)' >/etc/exports
exportfs -arv

systemctl start nfs
systemctl enable nfs
systemctl start rpcbind.service
systemctl enable rpcbind.service
showmount -e
firewall-cmd --add-service=nfs --permanent
firewall-cmd --reload

# node01
yum install nfs-utils rpcbind -y
