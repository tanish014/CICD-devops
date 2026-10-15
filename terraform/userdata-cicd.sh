#!/bin/bash
# EC2 #1 bootstrap: Docker + Jenkins on Ubuntu 22.04
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- 2 GB swap: a 1 GB instance needs it to survive package installs and image builds ---
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

apt-get update -y
apt-get install -y ca-certificates curl gnupg git openjdk-17-jre

# --- Docker Engine ---
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io
systemctl enable --now docker

# --- Jenkins (LTS) ---
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key -o /usr/share/keyrings/jenkins-keyring.asc
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list
apt-get update -y
apt-get install -y jenkins

# Cap the Jenkins JVM heap so Jenkins + Docker fit in 1 GB of RAM.
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf << 'OVERRIDE'
[Service]
Environment="JAVA_OPTS=-Djava.awt.headless=true -Xms128m -Xmx384m"
OVERRIDE
systemctl daemon-reload

# Let the jenkins user run docker, then restart so the group applies.
usermod -aG docker jenkins
systemctl enable jenkins
systemctl restart jenkins
