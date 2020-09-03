#!/bin/bash -v
# Make cloud-init output log readable by root.

# User Data for splunk EC2 instance creation  
sudo su - 
chmod 600 /var/log/cloud-init-output.log
yum update -y aws-cfn-bootstrap
yum update -y
yum install -y jq

adduser splunk --comment "Splunk User" --system --create-home --shell /bin/bash
#usermod --expiredate 1 splunk

mkdir /opt/splunk
#mkfs -t ext4 /dev/sdb
#echo "/dev/sdb    /opt/splunk        ext4     defaults,nofail 0   2" >> /etc/fstab
#mount -a

aws s3 cp s3://sdchoi-cf/code/splunk.tgz /tmp

tar -xzf /tmp/splunk.tgz -C /opt/splunk --strip-components=1
rm -f /tmp/splunk.tgz

echo "source /opt/splunk/bin/setSplunkEnv" >> /home/splunk/.bashrc
echo "[user_info]" > /opt/splunk/etc/system/local/user-seed.conf
echo "USERNAME = admin" >> /opt/splunk/etc/system/local/user-seed.conf
echo "PASSWORD = changeme" >> /opt/splunk/etc/system/local/user-seed.conf

touch /opt/splunk/etc/.ui_login

chown -R splunk:splunk /opt/splunk
sudo -u splunk /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt

/opt/splunk/bin/splunk enable boot-start -user splunk

cat << EOF > /tmp/init-thp-ulimits
# Disabling transparent huge pages
disable_thp() {
echo "Disabling transparent huge pages"
if test -f /sys/kernel/mm/transparent_hugepage/enabled; then
    echo never > /sys/kernel/mm/transparent_hugepage/enabled
fi
if test -f /sys/kernel/mm/transparent_hugepage/defrag; then
    echo never > /sys/kernel/mm/transparent_hugepage/defrag
fi
}

# Change ulimits
change_ulimit() {
ulimit -Sn 65535
ulimit -Hn 65535
ulimit -Su 20480
ulimit -Hu 20480
ulimit -Sf unlimited
ulimit -Hf unlimited
}
EOF
sed -i "/init\.d\/functions/r /tmp/init-thp-ulimits" /etc/init.d/splunk
sed -i "/start)$/a \    disable_thp\n    change_ulimit" /etc/init.d/splunk
rm /tmp/init-thp-ulimits

# Create 25-splunk.conf in limits.d to set ulimits when not using systemctl
echo "splunk           hard    core            0" >> /etc/security/limits.d/25-splunk.conf
echo "splunk           hard    maxlogins       10" >> /etc/security/limits.d/25-splunk.conf
echo "splunk           soft    nofile          65535" >> /etc/security/limits.d/25-splunk.conf
echo "splunk           hard    nofile          65535" >> /etc/security/limits.d/25-splunk.conf
echo "splunk           soft    nproc           20480" >> /etc/security/limits.d/25-splunk.conf
echo "splunk           hard    nproc           20480" >> /etc/security/limits.d/25-splunk.conf
echo "splunk           soft    fsize           unlimited" >> /etc/security/limits.d/25-splunk.conf
echo "splunk           hard    fsize           unlimited"  >> /etc/security/limits.d/25-splunk.conf

/opt/splunk/bin/splunk stop
cd /opt/splunk/etc/licenses
wget https://sdchoi.s3.ap-northeast-2.amazonaws.com/Splunk_Enterprise_NFR_Q3FY21.lic /opt/splunk/etc/licenses/Splunk_Enterprise_NFR_Q3FY21.lic

# /opt/splunk/bin/splunk clone-prep-clear-config
#rm -f /opt/splunk/var/log

systemctl daemon-reload

