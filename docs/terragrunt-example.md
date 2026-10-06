# Terragrunt example

Terragrunt passes `inputs` to the module as variables, so no Terragrunt-specific logic is needed. The module resolves the references by name and host name.

```hcl
terraform {
  source = "git::https://github.com/freevedo/terraform-azurerm-avm-res-cdn-profile.git//.?ref=claude/azure-frontdoor-terraform-fork-zozt36"
  # once merged and tagged: ...git//.?ref=v1.0.0
}

include "root" {
  path = find_in_parent_folders()
}

dependency "rg" {
  config_path = "../resource-group"
}

# Optional: only needed when a custom domain uses an Azure DNS zone
dependency "dns" {
  config_path = "../dns-zone"
}

locals {
  env = "prod"
}

inputs = {
  name                = "afd-myapp-${local.env}"
  location            = "westeurope"
  resource_group_name = dependency.rg.outputs.name
  sku                 = "Premium_AzureFrontDoor"

  front_door_endpoints = [
    { name = "myapp-${local.env}" }
  ]

  # Origins live inside their group. Group and origin names are optional.
  front_door_origin_groups = [
    {
      name = "app-og" # optional; omitted it becomes "app-contoso-com-og"
      origins = [
        { host_name = "app.contoso.com" },                            # name defaults to "app-contoso-com"
        { host_name = "api.contoso.com", name = "api", priority = 2 } # explicit name is kept as is
      ]
      health_probe   = { hp = { interval_in_seconds = 240, protocol = "Https" } }
      load_balancing = { lb = {} }
    }
  ]

  # Custom domains are identified by host_name; name is optional
  front_door_custom_domains = [
    {
      host_name   = "www.contoso.com"
      dns_zone_id = dependency.dns.outputs.zone_id
      tls         = {} # ManagedCertificate by default
    }
  ]

  front_door_routes = [
    {
      name                     = "default"
      endpoint_name            = "myapp-${local.env}"
      origin_host_names        = ["app.contoso.com", "api.contoso.com"] # the origin group is inferred
      custom_domain_host_names = ["www.contoso.com"]
      patterns_to_match        = ["/*"]
      supported_protocols      = ["Http", "Https"]
    }
  ]

  front_door_security_policies = [
    {
      name = "waf-policy"
      firewall = {
        front_door_firewall_policy_name = "waf-myapp"
        association = {
          endpoint_names    = ["myapp-${local.env}"]
          domain_host_names = ["www.contoso.com"]
          patterns_to_match = ["/*"]
        }
      }
    }
  ]
}
```

## Notes

- Everything is referenced by name or host name, never by a map key.
- A route lists `origin_host_names`; the module finds the origins and their origin group. All of a route's origins must belong to one origin group, and origin `host_name` values must be unique across all groups.
- Explicit `name` values are always used as given. Omitted names are derived from the host name (dots replaced by hyphens; origin groups also get the `-og` suffix).
- On existing deployments, set explicit names on origin groups, origins and custom domains. A derived name that differs from the name in Azure recreates the resource.
- This example has not been applied against real Azure.
