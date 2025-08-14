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

# Update packages
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

# Install containerd
echo "Installing containerd..."
sudo apt-get update && sudo apt-get install -y containerd.io || { echo "Failed to install containerd"; exit 1; }

# Configure containerd
echo "Configuring containerd..."
sudo containerd config default | sudo tee "$CONTAINERD_CONFIG" > /dev/null || { echo "Failed to generate containerd config"; exit 1; }
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' "$CONTAINERD_CONFIG" || { echo "Failed to modify containerd config"; exit 1; }
sudo systemctl restart containerd || { echo "Failed to restart containerd"; exit 1; }

# Set up K8S repository
echo "Setting up K8S repository..."
sudo mkdir -p -m 755 /etc/apt/keyrings || { echo "Failed to create keyrings directory"; exit 1; }
curl -fsSL "https://pkgs.kubernetes.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" | \
    sudo gpg --dearmor -o "$K8S_KEYRING_PATH" || { echo "Failed to install K8S GPG key"; exit 1; }

echo "deb [signed-by=$K8S_KEYRING_PATH] \
https://pkgs.kubernetes.io/core:/stable:/v${K8S_VERSION}/deb/ /" | \
    sudo tee /etc/apt/sources.list.d/kubernetes.list || { echo "Failed to add K8S repository"; exit 1; }

# Install K8S components
echo "Installing kubernetes components..."
sudo apt-get update || { echo "Failed to update package lists"; exit 1; }
sudo apt-get install -y kubeadm=$K8S_FULLVERSION kubelet=$K8S_FULLVERSION kubectl=$K8S_FULLVERSION|| { echo "Failed to install K8S packages"; exit 1; }
echo "kubeadm installation completed successfully!"
sudo apt-mark hold kubelet kubeadm kubectl || { echo "Failed to hold K8S packages"; exit 1; }

# Configure hosts file
echo "Configuring hosts file..."
cat << EOF | sudo tee /etc/hosts
$(hostname -i) $(hostname)
127.0.0.1 localhost
EOF

# ======== INIT CONTROL PLANE ========
echo "[INFO] Initializing Kubernetes control plane..."
sudo kubeadm init \
    --upload-certs \
    --node-name= "${CONTROL_PLANE_NODE_NAME}" \
    --control-plane-endpoint "${HOSTNAME}:6443" \
    --pod-network-cidr "${POD_CIDR}" \
    --kubernetes-version "${K8S_SUBVERSION}"

# ======== KUBECONFIG SETUP ========
echo "[INFO] Setting up kubeconfig for user..."
mkdir -p "${USER_HOME}/.kube"
sudo cp -i /etc/kubernetes/admin.conf "${USER_HOME}/.kube/config"
sudo chown "$(id -u)":"$(id -g)" "${USER_HOME}/.kube/config"

# ======== INSTALL WEAVE NET CNI ========
echo "[INFO] Installing Weave Net CNI..."
kubectl apply -f "https://reweave.azurewebsites.net/k8s/v${K8S_VERSION}/net.yaml"

# ======== VERIFY NODE STATUS ========
echo "[INFO] Visualize control-plane node..."
kubectl get nodes -o wide

echo "[SUCCESS] Kubernetes control plane is initialized and ready!"

sudo apt-get install bash-completion -y

echo
echo "-------- <exit and log back in> ---------- "
echo "type:"
echo "  source <(kubectl completion bash)"
echo "  source <(kubectl completion bash) >> $HOME/.bashrc"