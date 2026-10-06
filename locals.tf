locals {
  cdn_endpoint_diagnostics = { for k, v in var.cdn_endpoints : k => v if strcontains(var.sku, "AzureFrontDoor") == false && v.diagnostic_setting != null }
  custom_domain_routes = {
    for key, domain in azurerm_cdn_frontdoor_custom_domain.cds : key => [
      for route in try(azurerm_cdn_frontdoor_route.routes, []) : route.id
      if contains(coalesce(route.cdn_frontdoor_custom_domain_ids, []), domain.id)
    ]
  }
  filtered_epcds_for_security_policy = { for k, v in local.front_door_security_policies : k =>
    concat([for item in try(v.firewall.association.endpoint_names, []) : azurerm_cdn_frontdoor_endpoint.endpoints[item].id], [for item in try(v.firewall.association.domain_host_names, []) : azurerm_cdn_frontdoor_custom_domain.cds[item].id])
  }
  front_door_custom_domains    = { for v in var.front_door_custom_domains : v.host_name => merge(v, { name = coalesce(v.name, replace(v.host_name, ".", "-")) }) }
  front_door_endpoints         = { for v in var.front_door_endpoints : v.name => v }
  front_door_firewall_policies = { for v in var.front_door_firewall_policies : v.name => v }
  front_door_origin_groups = {
    for g in var.front_door_origin_groups : coalesce(g.name, "${replace(g.origins[0].host_name, ".", "-")}-og") => merge(g, { name = coalesce(g.name, "${replace(g.origins[0].host_name, ".", "-")}-og") })
  }
  front_door_origins = merge([
    for gname, g in local.front_door_origin_groups : {
      for o in g.origins : "${gname}/${coalesce(o.name, replace(o.host_name, ".", "-"))}" => merge(o, {
        name              = coalesce(o.name, replace(o.host_name, ".", "-"))
        origin_group_name = gname
      })
    }
  ]...)
  front_door_origin_keys_by_host_name = { for k, o in local.front_door_origins : o.host_name => k }
  front_door_route_origin_group_names = {
    for k, r in local.front_door_routes : k => r.origin_group_name != null ? r.origin_group_name : local.front_door_origins[local.front_door_origin_keys_by_host_name[r.origin_host_names[0]]].origin_group_name
  }
  front_door_route_origin_keys = {
    for k, r in local.front_door_routes : k => distinct(concat(
      [for n in r.origin_names : "${local.front_door_route_origin_group_names[k]}/${n}"],
      [for h in r.origin_host_names : local.front_door_origin_keys_by_host_name[h]]
    ))
  }
  front_door_routes            = { for v in var.front_door_routes : v.name => v }
  front_door_rules             = { for v in var.front_door_rules : "${v.rule_set_name}/${v.name}" => v }
  front_door_secrets           = { for v in var.front_door_secrets : v.name => v }
  front_door_security_policies = { for v in var.front_door_security_policies : v.name => v }
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
    for k, v in local.front_door_routes : k => [for cd in v.custom_domain_host_names : azurerm_cdn_frontdoor_custom_domain.cds[cd].id]
  }
  subscription_id = data.azapi_client_config.current.subscription_id
}
