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

# Wait for cert-manager to be ready before installing Rancher.
# The webhook is the last component to start and is critical for functionality.
echo "Waiting for cert-manager webhook to be ready..."
/var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml \
  wait --for=condition=Available deployment/cert-manager-webhook \
  --namespace cert-manager --timeout=300s
echo "cert-manager webhook is ready."

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
  --set registration.regCode="${rancher_prime_reg_code}" \
  --set agentTLSMode=system-store \
  --set features="rancher-ai"

# 9. Wait for Rancher and configure settings

# Wait for the Rancher deployment to become available before attempting to change settings.
echo "Waiting for Rancher deployment to be ready..."
/var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml \
  rollout status deployment/rancher -n cattle-system --timeout=600s
echo "Rancher deployment is ready."

# 10. Configure Rancher AI (Liz) with Google Gemini
echo "Configuring Rancher AI with Google Gemini..."

# Create the secret for the Gemini API key.
# Using apply with dry-run to make this step idempotent.
/var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml \
  create secret generic llm-provider-google-gemini \
  --namespace cattle-system \
  --from-literal=apiKey="${gemini_api_key}" \
  --dry-run=client -o yaml | /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml apply -f -

# Set the LLM provider to google-gemini
helm install rancher-ai-agent \
  --namespace cattle-ai-agent-system \
  --create-namespace \
  --set activeLlm=gemini \
  --set geminiLlmModel=gemini-3-flash-preview \
  --set googleApiKey="${gemini_api_key}" \
  oci://registry.suse.com/rancher/charts/rancher-ai-agent

# Final health check to ensure Rancher is fully available before script exits.
# This polls the ingress endpoint to confirm the application is responsive.
echo "Performing final health check on Rancher..."
timeout 300s bash -c 'while [[ "$(curl -k -s -o /dev/null -w ''%%{http_code}'' https://localhost/healthz)" != "200" ]]; do echo "Waiting for Rancher to be healthy..."; sleep 5; done'
if [ $? -ne 0 ]; then
  echo "Timed out waiting for Rancher to become healthy." >&2
  exit 1
fi
echo "Rancher is healthy and fully available."
