#!/bin/sh
#UPDATING DEBIAN
sudo -s
cd /root/
apt update
apt upgrade -y
apt install -y moreutils nfs-client wget sudo curl
sudo mkdir /storage
echo "192.168.191.17:/storage   /storage   nfs    auto  0  0" >> /etc/fstab
wget get.docker.io
sh index.html
sudo mkdir -p /opt/bin
sudo mkdir /ips

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
sudo cat <<EOF >/etc/systemd/system/zerotier.service;
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
sudo cat <<EOF >/etc/systemd/system/setup-network-environment.service;
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
sudo cat <<EOF >/lib/systemd/system/docker.service;
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
sudo cat <<EOF >/etc/systemd/system/onboot.service;
[Unit]
Description=start klouds stack
After=docker.service
After=network-online.target
After=zerotier.service
Requires=/etc/systemd/system/zerotier-one.service
Requires=docker.service
[Service]
ExecStart=/usr/bin/onboot
[Install]
WantedBy=multi-user.target
EOF

sudo cat <<EOF >/etc/systemd/system/onboot.service;
[Unit]
Description=remove nodes from kdaemon when they shut down
Requires=/etc/systemd/system/zerotier-one.service
Requires=docker.service
[Service]
ExecStart=/usr/bin/shutdown.service
[Install]
WantedBy=reboot.target
WantedBy=shutdown.target
EOF

#ONBOOT SCRIPT, which will start weave and scope, and put IP address info in a file at /id/ipinfo on the storage disk.
sudo cat <<EOF >/usr/bin/onboot;
#!/bin/sh
/usr/local/bin/weave launch weave.klouds.org
sudo weave expose > /ips/weave
export WEAVEIP=$(cat /ips/weave)
export ZT0_IPV4=$(ifdata -pa zt0)
/usr/local/bin/scope launch
export GOOGLEID=$(curl http://metadata.google.internal/computeMetadata/v1/instance/id -H "Metadata-Flavor: Google")
cat /etc/network-environment > /storage/ipinfo/$ID
curl -X POST -H "Content-Type: application/json" -H "Cache-Control: no-cache" -H "Postman-Token: 1c5e1b3a-d123-1f55-f3a6-06c08f1ef25f" -d '    {
        "name":"$ID",
        "d_ipaddr":"$ZT0_IPV4",
        "d_port": "2375",
    }' "http://192.168.191.17:4000/0.0/nodes/create"
EOF

cat <<EOF >/usr/bin/shutdown;
#!/bin/sh
/usr/local/bin/weave launch weave.klouds.org
sudo weave expose > /ips/weave
export WEAVEIP=$(cat /ips/weave)
export ZT0_IPV4=$(ifdata -pa zt0)
/usr/local/bin/scope launch
curl -X DELETE -H "Content-Type: application/json" -H "Cache-Control: no-cache" -H "Postman-Token: 1c5e1b3a-d123-1f55-f3a6-06c08f1ef25f" -d '    {
        "name":"$ID",
    }' "http://192.168.191.17:4000/0.0/nodes/create"
EOF

chmod a+x /usr/bin/shutdown
chmod a+x /usr/bin/onboot
systemctl daemon-reload
systemctl enable onboot.service
systemctl enable docker.service
systemctl enable setup-network-environment.service
systemctl enable zerotier.service
