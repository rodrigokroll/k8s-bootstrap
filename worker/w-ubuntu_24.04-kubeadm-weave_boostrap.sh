#!/bin/bash

# Configuration Variables
K8S_VERSION="1.33"
K8S_SUBVERSION="1.33.3"
K8S_FULLVERSION="1.33.0-1.1"
DOCKER_KEYRING_PATH="/etc/apt/keyrings/docker.gpg"
K8S_KEYRING_PATH="/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
CONTAINERD_CONFIG="/etc/containerd/config.toml"
HOSTNAME=`hostname`
POD_CIDR="10.0.0.0/16"
CONTROL_PLANE_NODE_NAME="cp"

# Update
sudo apt-get update && sudo apt-get upgrade -y
sudo apt install apt-transport-https software-properties-common lsb-release ca-certificates socat -y

# Disable swap
echo "Disabling swap..."
sudo swapoff -a || { echo "Failed to disable swap"; exit 1; }

# Load required kernel modules
echo "Loading kernel modules..."
sudo modprobe overlay || { echo "Failed to load overlay module"; exit 1; }
sudo modprobe br_netfilter || { echo "Failed to load br_netfilter module"; exit 1; }

# Configure sysctl parameters
echo "Configuring sysctl parameters..."
cat << EOF | sudo tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system || { echo "Failed to apply sysctl settings"; exit 1; }

# Install Docker's GPG key
echo "Setting up Docker repository..."
sudo mkdir -p /etc/apt/keyrings || { echo "Failed to create keyrings directory"; exit 1; }
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o "$DOCKER_KEYRING_PATH" || { echo "Failed to install Docker GPG key"; exit 1; }

echo "deb [arch=$(dpkg --print-architecture) signed-by=$DOCKER_KEYRING_PATH] \
https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install K8S components
echo "Installing kubernetes components..."
sudo apt-get update || { echo "Failed to update package lists"; exit 1; }
sudo apt-get install -y kubeadm=$K8S_FULLVERSION kubelet=$K8S_FULLVERSION kubectl=$K8S_FULLVERSION|| { echo "Failed to install K8S packages"; exit 1; }
echo "kubeadm installation completed successfully!"
sudo apt-mark hold kubelet kubeadm kubectl || { echo "Failed to hold K8S packages"; exit 1; }

# ======== INIT WORKER ========
echo "[INFO] Initializing Kubernetes worker..."
echo
echo "Login in control plane and type:"
echo "sudo kubeadm token create --print-join-command"
echo
echo -ne "run command in worker ... example:\n  $ kubeadm join cka-cp:6443 --token kcu55w.7jso85i0e2dsn05y \\n--discovery-token-ca-cert-hash\nsha256:0fb62b3c47bfd3af3c15d21f2ab6082fad1f913b244d5980816f8147ce9936ef"