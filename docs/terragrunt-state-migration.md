# Migrating existing infrastructure (key-based module to name-based module)

Earlier versions of this module addressed every child resource by a map key you chose, for example `azurerm_cdn_frontdoor_origin.origins["origin1_key"]`. This module addresses them by name, for example `azurerm_cdn_frontdoor_origin.origins["og1/origin1"]`. A different address means a different state entry, so Terraform would destroy and recreate the resource.

There are two ways to avoid that:

- **Option A (recommended): set `key` on every item.** No state change at all.
- **Option B: generate `moved` blocks in Terragrunt.** The state is rewritten once, through reviewed `moved` blocks.

## Option A: keep the old addresses with `key`

Every item in `front_door_*` has an optional `key`. When it is set, the module uses it as the resource address instead of the name, so the address stays exactly what it was. References between resources stay name-based, and the module resolves each name to its key internally. New deployments never set `key`.

Keep your existing key-based maps in Terragrunt unchanged, and let Terragrunt convert them to the new lists with `key = <old key>`. The conversion below was run with Terragrunt v0.69.10 and Terraform 1.9.8 against this module's real variable types and locals. Every resource instance came out with its old key (`ep1_key`, `og1_key`, `origin1_key`, `cd1_key`, `route1_key`, `rule1_key`, `secret1_key`, `waf1_key`, `sp1_key`). It has not been applied to real Azure resources, so run `terragrunt plan` first and expect no creates or destroys.

```hcl
terraform {
  source = "git::https://github.com/freevedo/terraform-azurerm-avm-res-cdn-profile.git//.?ref=claude/azure-frontdoor-terraform-fork-zozt36"
}

locals {
  # ---- existing key-based configuration, kept exactly as it was ----
  old_endpoints = {
    ep1_key = { name = "ep1" }
  }
  old_origin_groups = {
    og1_key = {
      name           = "og1"
      health_probe   = { hp1 = { interval_in_seconds = 240, protocol = "Https" } }
      load_balancing = { lb1 = {} }
    }
  }
  old_origins = {
    origin1_key = {
      name                           = "origin1"
      origin_group_key               = "og1_key"
      host_name                      = "a.contoso.com"
      certificate_name_check_enabled = true
      private_link = {
        pl = { request_message = "Please approve this connection", location = "westeurope", private_link_target_id = "id", target_type = "blob" }
      }
    }
    origin2_key = {
      name                           = "origin2"
      origin_group_key               = "og1_key"
      host_name                      = "b.contoso.com"
      certificate_name_check_enabled = false
    }
  }
  old_custom_domains = {
    cd1_key = {
      name      = "contoso1"
      host_name = "www.contoso.com"
      tls       = { certificate_type = "CustomerCertificate", cdn_frontdoor_secret_key = "secret1_key" }
    }
  }
  old_secrets = {
    secret1_key = { name = "cert", key_vault_certificate_id = "x" }
  }
  old_firewall_policies = {
    waf1_key = { name = "waf1", resource_group_name = "rg", sku_name = "Premium_AzureFrontDoor", mode = "Prevention" }
  }
  old_routes = {
    route1_key = {
      name                = "r1"
      endpoint_key        = "ep1_key"
      origin_group_key    = "og1_key"
      origin_keys         = ["origin1_key", "origin2_key"]
      custom_domain_keys  = ["cd1_key"]
      supported_protocols = ["Http", "Https"]
      patterns_to_match   = ["/*"]
    }
  }
  old_rules = {
    rule1_key = { name = "rule1", rule_set_name = "rs", origin_group_key = "og1_key", order = 1, actions = {}, conditions = {} }
  }
  old_security_policies = {
    sp1_key = {
      name = "sp1"
      firewall = {
        front_door_firewall_policy_key = "waf1_key"
        association = { endpoint_keys = ["ep1_key"], domain_keys = ["cd1_key"], patterns_to_match = ["/*"] }
      }
    }
  }
}

inputs = {
  name                = "afd-myapp-prod"
  location            = "westeurope"
  resource_group_name = "rg-myapp-prod"

  # ---- conversion: every old key becomes the optional `key`, references become names ----
  front_door_endpoints = [for k, v in local.old_endpoints : merge(v, { key = k })]

  front_door_origin_groups = [
    for gk, g in local.old_origin_groups : merge(g, {
      key = gk
      origins = [
        for ok, o in local.old_origins : merge(o, {
          key          = ok
          host_name    = o.host_name
          private_link = try(values(o.private_link)[0], null) # was a map, now a single object
        }) if o.origin_group_key == gk
      ]
    })
  ]

  front_door_custom_domains = [
    for k, v in local.old_custom_domains : merge(v, {
      key = k
      tls = { certificate_type = v.tls.certificate_type, cdn_frontdoor_secret_name = try(local.old_secrets[v.tls.cdn_frontdoor_secret_key].name, null) }
    })
  ]

  front_door_secrets           = [for k, v in local.old_secrets : merge(v, { key = k })]
  front_door_firewall_policies = [for k, v in local.old_firewall_policies : merge(v, { key = k })]

  front_door_routes = [
    for k, r in local.old_routes : merge(r, {
      key                      = k
      endpoint_name            = local.old_endpoints[r.endpoint_key].name
      origin_group_name        = local.old_origin_groups[r.origin_group_key].name
      origin_names             = [for ok in r.origin_keys : local.old_origins[ok].name]
      custom_domain_host_names = [for ck in try(r.custom_domain_keys, []) : local.old_custom_domains[ck].host_name]
    })
  ]

  front_door_rules = [
    for k, r in local.old_rules : merge(r, {
      key               = k
      origin_group_name = local.old_origin_groups[r.origin_group_key].name
    })
  ]

  front_door_security_policies = [
    for k, p in local.old_security_policies : {
      key  = k
      name = p.name
      firewall = {
        front_door_firewall_policy_name = local.old_firewall_policies[p.firewall.front_door_firewall_policy_key].name
        association = {
          endpoint_names    = [for ek in try(p.firewall.association.endpoint_keys, []) : local.old_endpoints[ek].name]
          domain_host_names = [for dk in try(p.firewall.association.domain_keys, []) : local.old_custom_domains[dk].host_name]
          patterns_to_match = p.firewall.association.patterns_to_match
        }
      }
    }
  ]
}
```

What the conversion does:

- every old map becomes a list, and the old map key becomes `key`
- `origin_group_key` on an origin is replaced by nesting the origin inside its group
- `private_link` on an origin was a map and is now a single object (`try(values(o.private_link)[0], null)`)
- routes, rules, custom domains and security policies swap their `*_key` references for names and host names
- the old extra attributes (`origin_group_key`, `endpoint_key` and so on) are dropped by the type conversion

Notes:

- A `key` must be unique within its own list. This is validated.
- Origin `key` values are the old origin keys, as they were never combined with the group.
- To move to name-based addresses later, remove `key` and follow Option B once with the same `legacy` table.

## Option B: generate `moved` blocks

Use this when you want the new name-based addresses. Terraform rewrites the state through `moved` blocks, without touching real resources. `moved` blocks need literal addresses, so the module cannot ship them for your keys. Terragrunt generates them from a small table of your old keys. This was tested with Terragrunt v0.69.10 and Terraform 1.9.8 against stand-in `terraform_data` resources: the plan reported each instance as `has moved` and `0 to add, 0 to change, 0 to destroy`.

### New address for each old key

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

### Steps

1. **Pin every name explicitly.** Set `name` on each origin group, origin and custom domain to the exact name that already exists in Azure. Derived names (host name with dots replaced by hyphens) are only for new resources. A name that differs from Azure recreates the resource.
2. **Fill in the `legacy` table** below with `old key = new key` pairs.
3. **Run `PLAN` with `migrate_state = true`.** Every instance should be reported as `has moved`, and the plan should show no create or destroy. If it does, a name does not match, so fix it and plan again.
4. **Apply**, which only rewrites the state.
5. **Remove** the `generate "moved"` block (or set `migrate_state = false`) and commit. Terraform rejects a `moved` block whose old key is still declared, so do not leave it enabled alongside key-based inputs.

### terragrunt.hcl

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

### Other options

- **Per resource:** `terragrunt state mv 'azurerm_cdn_frontdoor_origin.origins["origin1_key"]' 'azurerm_cdn_frontdoor_origin.origins["app-og/app-contoso-com"]'` does the same for one instance. It edits the state directly, so back it up first. The generated `moved` blocks are safer, because they are reviewed in the plan.
- **Finding your old keys and names:** `terragrunt state list` lists the old addresses, and `terragrunt state show '<address>'` shows the Azure name.
- **If the module is called as a child module** instead of being the Terragrunt root, the `moved` blocks must live in the calling configuration and use the `module.<name>.` prefix.

