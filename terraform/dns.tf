resource "aws_route53_record" "rancher_dns" {
  # Only create this resource if the create_dns_record variable is true
  count = var.create_dns_record ? 1 : 0

  # This depends on an external variable, so you must provide the zone_id
  zone_id = var.aws_route53_zone_id
  name    = var.rancher_hostname
  type    = "A"
  ttl     = 300

  # Point the A record to the public IP of the Azure Load Balancer
  # Note: azurerm_public_ip.lb_pip is not in the provided context, but is inferred from compute.tf
  records = [azurerm_public_ip.lb_pip.ip_address]
}