# RKE2 and Rancher Prime on Azure with Terraform

This project contains Terraform code to deploy a high-availability, three-node RKE2 cluster on Microsoft Azure. The first node bootstraps the cluster and installs Rancher Prime, while the other two nodes join as agents.

## Architecture

This configuration will create the following resources in your Azure subscription:

*   **Resource Group**: A container to hold all related resources.
*   **Virtual Network (VNet)**: An isolated network for the cluster.
*   **Subnet**: A dedicated subnet for the RKE2 nodes.
*   **Network Security Group (NSG)**: Firewall rules to control inbound traffic (SSH, HTTP, HTTPS, Kube-API).
*   **Availability Set**: To ensure high availability across the VMs.
*   **3 Virtual Machines**: SLES 15 SP7 nodes for the RKE2 cluster.
*   **3 Public IPs**: One for each VM to allow for direct SSH access.
*   **Azure Load Balancer**: To distribute traffic to the Rancher UI across the nodes.
*   **1 Public IP**: A static public IP for the Load Balancer frontend.

The first node runs a setup script via `user_data` to:
1.  Register the SLES operating system.
2.  Install RKE2 as a server.
3.  Install `cert-manager` for automated TLS certificate management.
4.  Deploy Rancher Prime via Helm, configured with Let's Encrypt.

The other two nodes run a simpler script to join the RKE2 cluster.

## Prerequisites

Before you begin, ensure you have the following installed and configured:

*   Terraform (>= 1.3.0)
*   Azure CLI
*   An active Azure Subscription.
*   An SSH public key (e.g., in `~/.ssh/id_rsa.pub`).

You will also need the following from the SUSE Customer Center:
*   A SUSE Linux Enterprise Server (SLES) registration code.
*   A Rancher Prime registration code.

## Configuration

1.  **Authenticate with Azure**: Log in using the Azure CLI.
    ```sh
    az login
    ```

2.  **Create a variables file**: This project uses a `terraform.tfvars` file to manage secrets and environment-specific settings. This file is ignored by Git. Create a file named `terraform.tfvars` in the `terraform/` directory and populate it with the required values.

    ```hcl
    # terraform/terraform.tfvars

    azure_location         = "westus"
    resource_group_name    = "rg-my-rancher-cluster"
    vm_size                = "Standard_D4s_v5"
    rancher_hostname       = "rancher.mydomain.com"
    letsencrypt_email      = "my-email@example.com"
    admin_username         = "azureuser"

    # --- Sensitive Values ---
    # Your SSH public key content
    ssh_public_key         = "ssh-rsa AAAA..."

    # SUSE and Rancher registration codes
    sles_reg_code          = "YOUR_SLES_REG_CODE"
    rancher_prime_reg_code = "YOUR_RANCHER_PRIME_REG_CODE"

    # Secrets for RKE2 and Rancher
    rke2_token             = "a_secure_random_string_for_rke2"
    rancher_bootstrap_password = "a_very_strong_password_for_rancher"
    ```

## Deployment

1.  **Initialize Terraform**: Navigate to the `terraform` directory and initialize the providers.
    ```sh
    cd terraform
    terraform init
    ```

2.  **Plan the deployment**: Review the resources that Terraform will create.
    ```sh
    terraform plan
    ```

3.  **Apply the configuration**: Deploy the infrastructure. This process will take several minutes as it involves provisioning VMs and bootstrapping Rancher.
    ```sh
    terraform apply
    ```

## Accessing Rancher

Once the deployment is complete, you need to manually create a DNS `A` record for your `rancher_hostname` that points to the public IP address of the Azure Load Balancer.

You can get the load balancer's public IP from the Terraform output. After the DNS has propagated, you can access the Rancher UI in your browser at `https://<your-rancher-hostname>`.

## Cleanup

To destroy all the resources created by this project, run the following command:

```sh
terraform destroy
```