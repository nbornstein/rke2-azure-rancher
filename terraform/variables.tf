variable "azure_location" {
  type        = string
  description = "Azure region for resources"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

variable "vm_size" {
  type        = string
  default     = "Standard_D4s_v5"
  description = "VM size for RKE2 control plane/worker nodes"
}

variable "downstream_node_count" {
  type        = number
  description = "Number of downstream RKE2/K3S SLES nodes to provision."
  default     = 1
}

variable "sles_reg_code" {
  type        = string
  description = "SUSE Linux Enterprise Server Registration Code"
  sensitive   = true
}

variable "rancher_prime_reg_code" {
  type        = string
  description = "SUSE Customer Center Registration Code for Rancher Prime"
  sensitive   = true
}

variable "rancher_hostname" {
  type        = string
  description = "FQDN for Rancher UI"
}

variable "domain_name" {
  type        = string
  description = "The base domain name for the deployment (e.g., mydomain.com)."
  default     = null
}

variable "rke2_token" {
  type        = string
  description = "Shared secret token for RKE2 nodes to join"
  sensitive   = true
}

variable "admin_username" {
  type        = string
  default     = "azureuser"
  description = "Admin username for SLES VMs"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH Public Key content for VM access"
  default     = null # Optional fallback
}

variable "rancher_bootstrap_password" {
  type        = string
  description = "The initial bootstrap password for the Rancher admin user."
  sensitive   = true
}

variable "letsencrypt_email" {
  type        = string
  description = "Email address for Let's Encrypt certificates."
}

variable "aws_route53_zone_id" {
  type        = string
  description = "The Route53 Zone ID where the rancher hostname CNAME will be created."
  default     = null
}

variable "create_dns_record" {
  type        = bool
  description = "If true, create a Route53 record for the Rancher hostname."
  default     = false
}

variable "gemini_api_key" {
  type        = string
  description = "API Key for Google Gemini to be used by Rancher's AI Assistant 'Liz'."
  sensitive   = true
}
