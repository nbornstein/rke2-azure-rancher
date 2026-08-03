#!/usr/bin/env bash
set -x

# 1. Register SLES with SUSE Customer Center
SUSEConnect -r "${sles_reg_code}"

# 2. Kernel & OS prep for RKE2
systemctl stop apparmor || true
systemctl disable apparmor || true

# 3. Create RKE2 config directory
mkdir -p /etc/rancher/rke2

cat <<EOF > /etc/rancher/rke2/config.yaml
token: "${rke2_token}"
tls-san:
  - "${lb_ip}"
  - "${rancher_hostname}"
cni:
  - canal
write-kubeconfig-mode: "0640"
EOF

# 4. Install & Start RKE2
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="server" sh -
systemctl enable rke2-server.service
systemctl start rke2-server.service

# 5. Environment setup for kubectl & Helm
export PATH=$PATH:/var/lib/rancher/rke2/bin
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

echo "export PATH=\$PATH:/var/lib/rancher/rke2/bin" >> /etc/profile
echo "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml" >> /etc/profile

# 6. Install Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 7. Install cert-manager
/var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml \
  apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.1/cert-manager.yaml

# Wait for cert-manager deployments
sleep 40

# 8. Deploy Rancher via Helm
helm repo add rancher-prime https://charts.rancher.com/server-charts/prime
helm repo update

/var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml create ns cattle-system || true

helm install rancher rancher-prime/rancher \
  --kubeconfig /etc/rancher/rke2/rke2.yaml \
  --namespace cattle-system \
  --set hostname=${rancher_hostname} \
  --set bootstrapPassword="${rancher_bootstrap_password}" \
  --set ingress.tls.source=letsEncrypt \
  --set letsEncrypt.email="${letsencrypt_email}" \
  --set letsEncrypt.ingress.class=nginx \
  --set registration.enabled=true \
  --set registration.regCode="${rancher_prime_reg_code}"

# 9. Wait for Rancher and configure settings

# Wait for the Rancher deployment to become available before attempting to change settings.
echo "Waiting for Rancher deployment to be ready..."
/var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml \
  wait --for=condition=Available \
  --namespace cattle-system \
  --timeout=600s \
  deployment/rancher
echo "Rancher deployment is ready."

# Set the agent-tls-mode to 'system-store' for downstream cluster agents.
echo "Setting agent-tls-mode to system-store..."
/var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml \
  patch setting agent-tls-mode --type=merge -p '{"value": "system-store"}'
echo "agent-tls-mode successfully set to system-store."
