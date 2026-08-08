locals {
  downstream_user_data_path    = "${path.module}/templates/downstream-node.sh.tpl"
  downstream_user_data_content = fileexists(local.downstream_user_data_path) ? templatefile(local.downstream_user_data_path, {
    sles_reg_code = var.sles_reg_code
  }) : ""
  # user_data must be null or a non-empty string. An empty string will cause a provider error.
  downstream_user_data = local.downstream_user_data_content == "" ? null : base64encode(local.downstream_user_data_content)
}

resource "azurerm_availability_set" "avset" {
  name                         = "avset-rke2"
  location                     = azurerm_resource_group.rg.location
  resource_group_name          = azurerm_resource_group.rg.name
  platform_fault_domain_count  = 2
  platform_update_domain_count = 5
  managed                      = true
}

# Public IPs for direct SSH management
resource "azurerm_public_ip" "node_pip" {
  count               = var.rke2_node_count
  name                = "pip-rke2-node-${count.index + 1}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "nic" {
  count               = var.rke2_node_count
  name                = "nic-rke2-node-${count.index + 1}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.node_pip[count.index].id
  }
}

resource "azurerm_network_interface_backend_address_pool_association" "nic_lb_assoc" {
  count                   = var.rke2_node_count
  network_interface_id    = azurerm_network_interface.nic[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.backend_pool.id
}

resource "azurerm_linux_virtual_machine" "vm" {
  count               = var.rke2_node_count
  name                = "vm-rke2-node-${count.index + 1}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size
  admin_username      = var.admin_username
  availability_set_id = azurerm_availability_set.avset.id

  network_interface_ids = [
    azurerm_network_interface.nic[count.index].id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key != null ? var.ssh_public_key : file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 80
  }

  source_image_reference {
    publisher = "SUSE"
    offer     = "sles-15-sp7" # Marketplace default for SLES 15
    sku       = "gen2"
    version   = "latest"
  }

  user_data = base64encode(
    count.index == 0 ?
    templatefile("${path.module}/templates/first-node.sh.tpl", {
    sles_reg_code          = var.sles_reg_code,
    rancher_prime_reg_code = var.rancher_prime_reg_code,
    rke2_token             = var.rke2_token,
    lb_ip                  = azurerm_public_ip.lb_pip.ip_address,
    rancher_hostname       = var.rancher_hostname,
    rancher_bootstrap_password = var.rancher_bootstrap_password,
    letsencrypt_email      = var.letsencrypt_email,
    gemini_api_key         = var.gemini_api_key,
    gemini_model           = var.gemini_model
  }) :
    templatefile("${path.module}/templates/join-node.sh.tpl", {
      sles_reg_code    = var.sles_reg_code,
      rke2_token       = var.rke2_token,
      lb_ip            = azurerm_public_ip.lb_pip.ip_address,
      first_node_ip    = azurerm_network_interface.nic[0].private_ip_address,
      rancher_hostname = var.rancher_hostname
    })
  )

}

# --- Downstream Nodes ---

# Public IPs for downstream nodes for direct SSH management
resource "azurerm_public_ip" "downstream_node_pip" {
  count               = var.downstream_node_count
  name                = "pip-downstream-node-${count.index + 1}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "downstream_nic" {
  count               = var.downstream_node_count
  name                = "nic-downstream-node-${count.index + 1}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.downstream_node_pip[count.index].id
  }
}

resource "azurerm_linux_virtual_machine" "downstream_vm" {
  count               = var.downstream_node_count
  name                = "vm-downstream-node-${count.index + 1}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size
  admin_username      = var.admin_username
  availability_set_id = azurerm_availability_set.avset.id

  network_interface_ids = [
    azurerm_network_interface.downstream_nic[count.index].id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key != null ? var.ssh_public_key : file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 80
  }

  source_image_reference {
    publisher = "SUSE"
    offer     = "sles-15-sp7"
    sku       = "gen2"
    version   = "latest"
  }

  # This user_data script is intended to prepare the node for joining a downstream cluster.
  # You will need to create a 'templates/downstream-node.sh.tpl' file.
  # A basic template would register the system with SUSE.
  user_data = local.downstream_user_data


}

# --- Destroy-time De-registration ---

# These null_resources act as a hook to run a de-registration script when
# the associated VMs are destroyed. This pattern is necessary because a
# destroy-time provisioner cannot directly reference variables like var.scc_username.
#
# By storing the necessary data in the 'triggers' map, the values are snapshotted
# in the Terraform state and become accessible to the provisioner via 'self.triggers'
# during the destroy phase.

resource "null_resource" "scc_deregister_rancher_manager" {
  # Only create this resource if SCC credentials are provided. It runs only once
  # to de-register the single Rancher Manager instance.
  count = var.scc_username != null && var.scc_password != null ? 1 : 0

  triggers = {
    # We are targeting the Rancher Manager registration, which is identified
    # in SCC by the FQDN of the Rancher instance.
    scc_system_hostname = var.rancher_hostname
    scc_username        = var.scc_username
    scc_password        = var.scc_password
    script_path         = "${path.module}/deregister-scc.sh"
  }

  provisioner "local-exec" {
    when    = destroy
    command = self.triggers.script_path

    environment = {
      SCC_USERNAME    = self.triggers.scc_username
      SCC_PASSWORD    = self.triggers.scc_password
      SYSTEM_HOSTNAME = self.triggers.scc_system_hostname
    }
  }
}
