resource "azurerm_cdn_frontdoor_endpoint" "endpoints" {
  for_each = local.front_door_endpoints

  cdn_frontdoor_profile_id = azapi_resource.front_door_profile.id
  name                     = each.value.name
  enabled                  = each.value.enabled
  tags                     = each.value.tags != null ? each.value.tags : var.tags
}

resource "azurerm_cdn_frontdoor_route" "routes" {
  for_each = local.front_door_routes

  cdn_frontdoor_endpoint_id       = azurerm_cdn_frontdoor_endpoint.endpoints[local.front_door_endpoint_keys_by_name[each.value.endpoint_name]].id
  cdn_frontdoor_origin_group_id   = azurerm_cdn_frontdoor_origin_group.origin_groups[local.front_door_origin_group_keys_by_name[local.front_door_route_origin_group_names[each.key]]].id
  name                            = each.value.name
  patterns_to_match               = each.value.patterns_to_match
  supported_protocols             = each.value.supported_protocols
  cdn_frontdoor_custom_domain_ids = local.route_custom_domains[each.key]
  cdn_frontdoor_origin_ids        = [for k in local.front_door_route_origin_keys[each.key] : azurerm_cdn_frontdoor_origin.origins[k].id]
  cdn_frontdoor_origin_path       = each.value.cdn_frontdoor_origin_path
  cdn_frontdoor_rule_set_ids      = [for k, v in azurerm_cdn_frontdoor_rule_set.rule_set : v.id if contains(coalesce(each.value.rule_set_names, [""]), v.name)]
  enabled                         = each.value.enabled
  forwarding_protocol             = each.value.forwarding_protocol
  https_redirect_enabled          = each.value.https_redirect_enabled
  link_to_default_domain          = each.value.link_to_default_domain

  dynamic "cache" {
    for_each = each.value.cache

    content {
      compression_enabled           = cache.value["compression_enabled"]
      content_types_to_compress     = cache.value["content_types_to_compress"]
      query_string_caching_behavior = cache.value["query_string_caching_behavior"]
      query_strings                 = cache.value["query_strings"]
    }
  }

  lifecycle {
    precondition {
      condition     = alltrue([for k in local.front_door_route_origin_keys[each.key] : local.front_door_origins[k].origin_group_name == local.front_door_route_origin_group_names[each.key]])
      error_message = "Route ${each.key}: all origins must belong to origin group ${local.front_door_route_origin_group_names[each.key]}."
    }
  }

  depends_on = [azurerm_cdn_frontdoor_origin.origins, azurerm_cdn_frontdoor_endpoint.endpoints, azurerm_cdn_frontdoor_custom_domain.cds]
}
