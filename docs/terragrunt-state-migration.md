# Migrating existing infrastructure (key-based state to name-based)

Earlier versions of this module addressed every child resource by a map key you chose, for example `azurerm_cdn_frontdoor_origin.origins["origin1_key"]`. This module addresses them by name, for example `azurerm_cdn_frontdoor_origin.origins["og1/origin1"]`. Generating keys in Terragrunt does not help, because the module no longer takes keys. What has to change is the **address in the state**, and Terraform does that without touching real resources through `moved` blocks.

`moved` blocks need literal addresses, so the module cannot ship them for your keys. Terragrunt can generate them from a small table of your old keys. This pattern was tested with Terragrunt v0.69.10 and Terraform 1.9.8 against stand-in `terraform_data` resources: the plan reported each instance as `has moved` and `0 to add, 0 to change, 0 to destroy`. It has not been run against real Azure resources.

## New address for each old key

| Old input | Resource address | Old key | New key |
|---|---|---|---|
| `front_door_endpoints` | `azurerm_cdn_frontdoor_endpoint.endpoints` | your key | endpoint `name` |
| `front_door_origin_groups` | `azurerm_cdn_frontdoor_origin_group.origin_groups` | your key | origin group name |
| `front_door_origins` | `azurerm_cdn_frontdoor_origin.origins` | your key | `<origin group name>/<origin name>` |
| `front_door_custom_domains` | `azurerm_cdn_frontdoor_custom_domain.cds` and `azurerm_cdn_frontdoor_custom_domain_association.association` | your key | custom domain `host_name` |
| `front_door_routes` | `azurerm_cdn_frontdoor_route.routes` | your key | route `name` |
| `front_door_rules` | `azurerm_cdn_frontdoor_rule.rules` | your key | `<rule set name>/<rule name>` |
| `front_door_secrets` | `azurerm_cdn_frontdoor_secret.frontdoorsecret` | your key | secret `name` |
| `front_door_firewall_policies` | `azurerm_cdn_frontdoor_firewall_policy.wafs` | your key | firewall policy `name` |
| `front_door_security_policies` | `azurerm_cdn_frontdoor_security_policy.security_policies` | your key | security policy `name` |

Rule sets (`front_door_rule_sets`) were already keyed by name and need no move.

## Steps

1. **Pin every name explicitly.** Set `name` on each origin group, origin and custom domain to the exact name that already exists in Azure. Derived names (host name with dots replaced by hyphens) are only for new resources. A name that differs from Azure recreates the resource.
2. **Fill in the `legacy` table** below with `old key = new key` pairs.
3. **Run `PLAN` with `migrate_state = true`.** Every instance should be reported as `has moved`, and the plan should show no create or destroy. If it does, a name does not match, so fix it and plan again.
4. **Apply**, which only rewrites the state.
5. **Remove** the `generate "moved"` block (or set `migrate_state = false`) and commit. Terraform rejects a `moved` block whose old key is still declared, so do not leave it enabled alongside key-based inputs.

## terragrunt.hcl

```hcl
terraform {
  source = "git::https://github.com/freevedo/terraform-azurerm-avm-res-cdn-profile.git//.?ref=claude/azure-frontdoor-terraform-fork-zozt36"
}

include "root" {
  path = find_in_parent_folders()
}

locals {
  # Set to true for the migration run, then back to false (or delete the generate block)
  migrate_state = true

  # old map key = new name-based key (see the table above)
  legacy = {
    endpoints         = { ep1_key = "myapp-prod" }
    origin_groups     = { og1_key = "app-og" }
    origins           = { origin1_key = "app-og/app-contoso-com", origin2_key = "app-og/api" }
    custom_domains    = { cd1_key = "www.contoso.com" }
    routes            = { route1_key = "default" }
    rules             = { rule1_key = "ruleset1/examplerule1" }
    secrets           = { secret1_key = "Front-door-certificate" }
    firewall_policies = { fd_waf1_key = "waf-myapp" }
    security_policies = { secpol1_key = "waf-policy" }
  }

  # resource addresses to move for each kind
  kinds = {
    endpoints         = ["azurerm_cdn_frontdoor_endpoint.endpoints"]
    origin_groups     = ["azurerm_cdn_frontdoor_origin_group.origin_groups"]
    origins           = ["azurerm_cdn_frontdoor_origin.origins"]
    custom_domains    = ["azurerm_cdn_frontdoor_custom_domain.cds", "azurerm_cdn_frontdoor_custom_domain_association.association"]
    routes            = ["azurerm_cdn_frontdoor_route.routes"]
    rules             = ["azurerm_cdn_frontdoor_rule.rules"]
    secrets           = ["azurerm_cdn_frontdoor_secret.frontdoorsecret"]
    firewall_policies = ["azurerm_cdn_frontdoor_firewall_policy.wafs"]
    security_policies = ["azurerm_cdn_frontdoor_security_policy.security_policies"]
  }

  moves = !local.migrate_state ? [] : flatten([
    for kind, pairs in local.legacy : [
      for old, new in pairs : [
        for addr in local.kinds[kind] : { addr = addr, from = old, to = new }
      ]
    ]
  ])
}

# Generates moved.tf next to the module code, only while migrate_state is true
generate "moved" {
  path      = "moved.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
%{for m in local.moves~}
moved {
  from = ${m.addr}["${m.from}"]
  to   = ${m.addr}["${m.to}"]
}
%{endfor~}
EOT
}

inputs = {
  name                = "afd-myapp-prod"
  location            = "westeurope"
  resource_group_name = "rg-myapp-prod"
  sku                 = "Premium_AzureFrontDoor"

  front_door_endpoints = [{ name = "myapp-prod" }]

  front_door_origin_groups = [
    {
      name = "app-og" # pinned to the existing Azure name
      origins = [
        { host_name = "app.contoso.com", name = "app-contoso-com" },
        { host_name = "api.contoso.com", name = "api" }
      ]
      health_probe   = { hp = { interval_in_seconds = 240, protocol = "Https" } }
      load_balancing = { lb = {} }
    }
  ]

  front_door_custom_domains = [
    { host_name = "www.contoso.com", name = "www-contoso-com", tls = {} }
  ]

  front_door_routes = [
    {
      name                     = "default"
      endpoint_name            = "myapp-prod"
      origin_host_names        = ["app.contoso.com", "api.contoso.com"]
      custom_domain_host_names = ["www.contoso.com"]
      patterns_to_match        = ["/*"]
      supported_protocols      = ["Http", "Https"]
    }
  ]
}
```

## Other options

- **Per resource:** `terragrunt state mv 'azurerm_cdn_frontdoor_origin.origins["origin1_key"]' 'azurerm_cdn_frontdoor_origin.origins["app-og/app-contoso-com"]'` does the same for one instance. It edits the state directly, so back it up first. The generated `moved` blocks are safer, because they are reviewed in the plan.
- **Finding your old keys and names:** `terragrunt state list` lists the old addresses, and `terragrunt state show '<address>'` shows the Azure name.
- **If the module is called as a child module** instead of being the Terragrunt root, the `moved` blocks must live in the calling configuration and use the `module.<name>.` prefix.
