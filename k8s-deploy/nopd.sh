IP_PASSWORD=./ip-password.txt

rpm -qa | grep expect >>/dev/null

if [ $? -eq 0 ]; then
  echo "expect already install."
else
  yum install expect -y
fi

# batch ssh Certification
for IP in $(cat $IP_PASSWORD); do
  ip=$(echo "$IP" | cut -f1 -d ":")
  password=$(echo "$IP" | cut -f2 -d ":")

  # begin expect
  expect -c "
  spawn ssh-copy-id -i /root/.ssh/id_dsa.pub root@$ip
        expect {
                  \"*yes/no*\" {send \"yes\r\"; exp_continue}
                  \"*password*\" {send \"$password\r\"; exp_continue}
                  \"*Password*\" {send \"$password\r\";}
        }
    "
done

# use ssh batch excute command

for hostip in $(cat $IP_PASSWORD | cut -f1 -d ":"); do
  ssh root@$hostip 'uptime'
done
