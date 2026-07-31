resource "aws_route53_record" "rancher_dns" {
  # This resource is created only if create_dns_record is true and a zone ID is provided.
  # It assumes an azurerm_public_ip resource named "lb_pip" exists for the load balancer.
  count = var.create_dns_record && var.aws_route53_zone_id != null ? 1 : 0

  # This depends on an external variable, so you must provide the zone_id
  zone_id = var.aws_route53_zone_id
  name    = var.rancher_hostname
  allow_overwrite = true
  type    = "A"
  ttl     = 300

  # Point the A record to the public IP of the Azure Load Balancer
  # Note: azurerm_public_ip.lb_pip is not in the provided context, but is inferred from compute.tf
  records = [azurerm_public_ip.lb_pip.ip_address]
}

resource "aws_route53_record" "rancher_node_dns" {
  # Create one record for each VM if create_dns_record is true.
  # This assumes 3 VMs are being created.
  count = var.create_dns_record && var.aws_route53_zone_id != null && var.domain_name != null ? 3 : 0

  zone_id = var.aws_route53_zone_id
  # Creates rancher-node1.suse-southeast.com, rancher-node2.suse-southeast.com, etc.
  name            = "rancher-node${count.index + 1}.${var.domain_name}"
  allow_overwrite = true
  type            = "A"
  ttl             = 300

  # Point the A record to the public IP of the corresponding Azure VM
  # Note: azurerm_public_ip.node_pip is inferred from compute.tf and is assumed to have a count of 3.
  records = [azurerm_public_ip.node_pip[count.index].ip_address]
}