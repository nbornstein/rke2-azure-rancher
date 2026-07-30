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
  count               = 3
  name                = "pip-rke2-node-${count.index + 1}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "nic" {
  count               = 3
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
  count                   = 3
  network_interface_id    = azurerm_network_interface.nic[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.backend_pool.id
}

resource "azurerm_linux_virtual_machine" "vm" {
  count               = 3
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
    offer     = "sles-15-sp5" # Marketplace default for SLES 15
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
    rancher_hostname       = var.rancher_hostname
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
