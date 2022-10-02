1、在机器上添加额外磁盘使用local pv的方式承载pod; 添加额外磁盘是为了不影响操作系统所在磁盘的IO 性能
重启

```
[root@k8s-worker-1 dev]# fdisk -l

磁盘 /dev/sda：53.7 GB, 53687091200 字节，104857600 个扇区
Units = 扇区 of 1 * 512 = 512 bytes
扇区大小(逻辑/物理)：512 字节 / 512 字节
I/O 大小(最小/最佳)：512 字节 / 512 字节
磁盘标签类型：dos
磁盘标识符：0x000b35d9

   设备 Boot      Start         End      Blocks   Id  System
/dev/sda1   *        2048     2099199     1048576   83  Linux
/dev/sda2         2099200   104857599    51379200   8e  Linux LVM

磁盘 /dev/sdb：21.5 GB, 21474836480 字节，41943040 个扇区
Units = 扇区 of 1 * 512 = 512 bytes
扇区大小(逻辑/物理)：512 字节 / 512 字节
I/O 大小(最小/最佳)：512 字节 / 512 字节

```




# 在node-1上执行
mkdir -p /mnt/disks/vol1
# 分区  m n e \n \n \n w
fdisk /dev/sdb
partprobe
# 格式化
mkfs -t ext4 -c /dev/sdb

# 内存型
# mount -t tmpfs $vol /mnt/disks/$vol


mount /dev/sdb /mnt/disks/vol1
df -h

# 开机自动挂载
# 查看设备
blkid /dev/sdb

echo `blkid /dev/sdb|awk '{print $2}' |sed 's/"//g'`  /mnt/disks/vol1  ext4 defaults  0  0 >> /etc/fstab
