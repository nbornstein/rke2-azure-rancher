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