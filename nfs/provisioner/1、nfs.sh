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
#
#
#
#  -----------------------ubuntu
sudo apt-get install nfs-kernel-server rpcbind selinux-utils nfs-common -y

rm -rf /nfs
mkdir -p /nfs
chown -R nobody:nobody /nfs
echo '/nfs   192.168.0.0/16(rw,async,no_root_squash)' >/etc/exports
exportfs -arv

sudo /etc/init.d/nfs-kernel-server start

## client
# sudo apt-get install nfs-common
# mkdir -p /data/nfs
# mount 192.168.188.102:/var/nfs /data/nfs
