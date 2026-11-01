resource "aws_ssm_parameter" "this" {
  for_each = var.parameters

  name        = "${coalesce(each.value.prefix, var.parameter_prefix)}/${each.key}"
  description = each.value.description
  type        = each.value.type
  tier        = "Standard"
  data_type   = "text"
  key_id      = each.value.key_id
  tags        = each.value.tags

  # Write-only values are omitted from Terraform state and saved plans.
  value_wo         = var.parameter_values[each.key]
  value_wo_version = each.value.value_version
}
