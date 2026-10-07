locals {
  cdn_endpoint_diagnostics = { for k, v in var.cdn_endpoints : k => v if strcontains(var.sku, "AzureFrontDoor") == false && v.diagnostic_setting != null }
  custom_domain_routes = {
    for key, domain in azurerm_cdn_frontdoor_custom_domain.cds : key => [
      for route in try(azurerm_cdn_frontdoor_route.routes, []) : route.id
      if contains(coalesce(route.cdn_frontdoor_custom_domain_ids, []), domain.id)
    ]
  }
  filtered_epcds_for_security_policy = { for k, v in local.front_door_security_policies : k =>
    concat([for item in try(v.firewall.association.endpoint_names, []) : azurerm_cdn_frontdoor_endpoint.endpoints[local.front_door_endpoint_keys_by_name[item]].id], [for item in try(v.firewall.association.domain_host_names, []) : azurerm_cdn_frontdoor_custom_domain.cds[local.front_door_custom_domain_keys_by_host_name[item]].id])
  }
  # Every Front Door resource is keyed by the optional `key` of its item, falling back to its name (or host name).
  # `key` only exists to keep the addresses of resources created by the key-based version of this module.
  front_door_custom_domain_keys_by_host_name = { for k, v in local.front_door_custom_domains : v.host_name => k }
  front_door_custom_domains = {
    for v in var.front_door_custom_domains : coalesce(v.key, v.host_name) => merge(v, { name = coalesce(v.name, replace(v.host_name, ".", "-")) })
  }
  front_door_endpoint_keys_by_name        = { for k, v in local.front_door_endpoints : v.name => k }
  front_door_endpoints                    = { for v in var.front_door_endpoints : coalesce(v.key, v.name) => v }
  front_door_firewall_policies            = { for v in var.front_door_firewall_policies : coalesce(v.key, v.name) => v }
  front_door_firewall_policy_keys_by_name = { for k, v in local.front_door_firewall_policies : v.name => k }
  front_door_origin_group_keys_by_name    = { for k, v in local.front_door_origin_groups : v.name => k }
  front_door_origin_groups = {
    for g in var.front_door_origin_groups : coalesce(g.key, g.name, "${replace(g.origins[0].host_name, ".", "-")}-og") => merge(g, { name = coalesce(g.name, "${replace(g.origins[0].host_name, ".", "-")}-og") })
  }
  front_door_origin_keys_by_group_and_name = { for k, o in local.front_door_origins : "${o.origin_group_name}/${o.name}" => k }
  front_door_origin_keys_by_host_name      = { for k, o in local.front_door_origins : o.host_name => k }
  front_door_origins = merge([
    for gkey, g in local.front_door_origin_groups : {
      for o in g.origins : coalesce(o.key, "${g.name}/${coalesce(o.name, replace(o.host_name, ".", "-"))}") => merge(o, {
        name              = coalesce(o.name, replace(o.host_name, ".", "-"))
        origin_group_key  = gkey
        origin_group_name = g.name
      })
    }
  ]...)
  front_door_route_origin_group_names = {
    for k, r in local.front_door_routes : k => r.origin_group_name != null ? r.origin_group_name : local.front_door_origins[local.front_door_origin_keys_by_host_name[r.origin_host_names[0]]].origin_group_name
  }
  front_door_route_origin_keys = {
    for k, r in local.front_door_routes : k => distinct(concat(
      [for n in r.origin_names : local.front_door_origin_keys_by_group_and_name["${local.front_door_route_origin_group_names[k]}/${n}"]],
      [for h in r.origin_host_names : local.front_door_origin_keys_by_host_name[h]]
    ))
  }
  front_door_routes              = { for v in var.front_door_routes : coalesce(v.key, v.name) => v }
  front_door_rules               = { for v in var.front_door_rules : coalesce(v.key, "${v.rule_set_name}/${v.name}") => v }
  front_door_secret_keys_by_name = { for k, v in local.front_door_secrets : v.name => k }
  front_door_secrets             = { for v in var.front_door_secrets : coalesce(v.key, v.name) => v }
  front_door_security_policies   = { for v in var.front_door_security_policies : coalesce(v.key, v.name) => v }
  managed_identities = {
    system_assigned_user_assigned = (var.managed_identities.system_assigned || length(var.managed_identities.user_assigned_resource_ids) > 0) ? {
      this = {
        type                       = var.managed_identities.system_assigned && length(var.managed_identities.user_assigned_resource_ids) > 0 ? "SystemAssigned, UserAssigned" : length(var.managed_identities.user_assigned_resource_ids) > 0 ? "UserAssigned" : "SystemAssigned"
        user_assigned_resource_ids = var.managed_identities.user_assigned_resource_ids
      }
    } : {}
    system_assigned = var.managed_identities.system_assigned ? {
      this = {
        type = "SystemAssigned"
      }
    } : {}
    user_assigned = length(var.managed_identities.user_assigned_resource_ids) > 0 ? {
      this = {
        type                       = "UserAssigned"
        user_assigned_resource_ids = var.managed_identities.user_assigned_resource_ids
      }
    } : {}
  }
  resource_group_id                  = provider::azapi::subscription_resource_id(local.subscription_id, local.resource_type, local.resource_names)
  resource_names                     = [var.resource_group_name]
  resource_type                      = "Microsoft.Resources/resourceGroups"
  role_definition_resource_substring = "providers/Microsoft.Authorization/roleDefinitions"
  route_custom_domains = {
    for k, v in local.front_door_routes : k => [for cd in v.custom_domain_host_names : azurerm_cdn_frontdoor_custom_domain.cds[local.front_door_custom_domain_keys_by_host_name[cd]].id]
  }
  subscription_id = data.azapi_client_config.current.subscription_id
}
