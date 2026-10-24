terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

provider "cloudflare" {}

variable "account_id" {
  type = string
}

variable "zone_id" {
  type = string
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "jellyfin" {
  account_id = var.account_id
  name       = "jellyfin"
  config_src = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "jellyfin" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.jellyfin.id
}

resource "cloudflare_dns_record" "jellyfin" {
  zone_id = var.zone_id
  name    = "jellyfin.enucatl.com"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.jellyfin.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "jellyfin" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.jellyfin.id
  source     = "cloudflare"
  config = {
    ingress = [
      {
        hostname = "jellyfin.enucatl.com"
        service  = "http://jellyfin:8096"
      },
      { service = "http_status:404" }
    ]
  }
}

output "tunnel_token" {
  value     = data.cloudflare_zero_trust_tunnel_cloudflared_token.jellyfin.token
  sensitive = true
}
