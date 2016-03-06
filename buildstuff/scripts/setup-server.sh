#!/bin/sh
#UPDATING DEBIAN
sudo -s
cd /root/
mkdir /root/config
mkdir /root/go
apt update
apt upgrade -y
apt install -y moreutils nfs-client nfs-server wget sudo curl
sudo mkdir /storage
echo "/dev/sdb  /storage   btrfs    auto  0  0" >> /etc/fstab
echo "/storage       192.168.0.0/16(rw,fsid=0,insecure,no_subtree_check,async)" >> /etc/exports
wget get.docker.io
sh index.html
sudo mkdir -p /opt/bin
sudo mkdir /ips

#INSTALL RETHINKDB
echo "deb http://download.rethinkdb.com/apt `lsb_release -cs` main" | sudo tee /etc/apt/sources.list.d/rethinkdb.list
wget -qO- https://download.rethinkdb.com/apt/pubkey.gpg | sudo apt-key add -
sudo apt-get update
sudo apt-get install -y rethinkdb

#DOWNLOAD AND INSTALL GOLANG
wget https://storage.googleapis.com/golang/go1.6.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.6.linux-amd64.tar.gz

#DOWNLOADING NETWORK COMPONENTS
sudo curl -L git.io/weave -o /usr/local/bin/weave
sudo wget -O /usr/local/bin/scope https://git.io/scope
sudo wget https://download.zerotier.com/dist/zerotier-one_1.1.4_amd64.deb
sudo wget -N -P /opt/bin https://github.com/kelseyhightower/setup-network-environment/releases/download/v1.0.0/setup-network-environment

#MARKING NETWORK COMPONENTS RUNNABLE
sudo chmod a+x /usr/local/bin/weave
sudo chmod a+x /usr/local/bin/scope
sudo chmod a+x /opt/bin/setup-network-environment

#INSTALLING ZEROTIER
sudo dpkg -i zerotier-one_1.1.4_amd64.deb

#ZEROTIER SYSTEMD UNIT
cat <<EOF >/etc/systemd/system/zerotier.service;
[Unit]
Description=ZeroTier
After=network-online.target
Before=docker.service
Before=setup-network-environment.service
Requires=network-online.target
[Service]
ExecStart=/usr/bin/zerotier-cli join e5cd7a9e1c87b1c8
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF

#SYSTEMD UNIT FOR kelseyhightower'S NETWORK-ENVIORNMENT-SERVICE WHICH ENSURES THAT IP ADDRESSES ARE ACCESSIBLE AT /etc/network-environment
cat <<EOF >/etc/systemd/system/setup-network-environment.service;
[Unit]
Description=Setup Network Environment
Documentation=https://github.com/kelseyhightower/setup-network-environment
Requires=network-online.target
Before=docker.socket
Before=docker.service
After=network-online.target
After=zerotier.service
[Service]
ExecStart=/opt/bin/setup-network-environment
RemainAfterExit=yes
Type=oneshot
[Install]
WantedBy=multi-user.target
EOF

#DOCKER SYSTEMD UNIT FILE, LAUNCHES DOCKER WITH PORT OPEN ON ZEROTIER ADDRESS REPORTED BY network-environment-service
cat <<EOF >/lib/systemd/system/docker.service;
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network.target docker.socket
After=setup-network-environment.service
After=network-online.target
Requires=docker.socket
[Service]
Type=notify
EnvironmentFile=/etc/network-environment
ExecStart=/usr/bin/docker daemon -H fd:// -H ${ZT0_IPV4}:2375
MountFlags=slave
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity
TimeoutStartSec=0
[Install]
WantedBy=multi-user.target
EOF

#ONBOOT SYSTEMD UNIT FILE, RUNS KLOUDS' ONBOOT SCRIPT, WHICH CONNECTS THE VM TO KLOUDS' NETWORK
cat <<EOF >/etc/systemd/system/server-onboot.service;
[Unit]
Description=start klouds stack
After=docker.service
After=network-online.target
After=zerotier.service
Requires=/etc/systemd/system/zerotier-one.service
Requires=docker.service
[Service]
ExecStart=/usr/bin/server-onboot
[Install]
WantedBy=multi-user.target
EOF

#ONBOOT SCRIPT, which will start weave and scope, and put IP address info in a file at /storage/server/$id/ipinfo on the storage disk.
cat <<EOF >/usr/bin/server-onboot;
#!/bin/sh
systemctl daemon-reload
export ID=$(curl http://metadata.google.internal/computeMetadata/v1/instance/id -H "Metadata-Flavor: Google")
/usr/local/bin/weave launch
weave expose > /storage/server/$ID/weave
export WEAVEIP=$(cat /storage/server/$ID/weave)
export ZT0_IPV4=$(ifdata -pa zt0)
/usr/local/bin/scope launch
cat /etc/network-environment > /storage/server/$ID/ipinfo/
/usr/bin/kDaemongrab
cd /root
kDaemon
EOF

#SERVER SHUTDOWN SCRIPT, YET TO BE COMPLETED
cat <<EOF >/usr/bin/server-shutdown;
hello world
EOF

#A LITTLE SCRIPT THAT WILL ENSURE THAT KDAEMON CAN EASILY BE REFRESHED TO THE LATEST VERSION.  IT IS CALLED BY THE ONBOOT SCRIPT.
cat <<EOF >/usr/bin/kDaemongrab;
export GOPATH = /root/go
export PATH=$PATH:/root/go/bin
go get github.com/klouds/kDaemon
cp /root/go/bin/kDaemon /usr/bin/kDaemon
EOF

cat <<EOF >/root/config/app.conf;
[default]
bind_ip = 127.0.0.1
api_port = 4000
rethinkdb_host = 127.0.0.1
rethinkdb_port = 28015
rethinkdb_dbname = stupiddbname
api_version = 0.0
EOF

chmod a+x /usr/bin/server-shutdown
chmod a+x /usr/bin/server-onboot
systemctl daemon-reload
systemctl enable server-onboot.service
systemctl enable docker.service
systemctl enable setup-network-environment.service
systemctl enable zerotier.service