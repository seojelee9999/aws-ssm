output "parameter_names" {
  description = "Parameter paths only; values are never output."
  value       = { for key, parameter in aws_ssm_parameter.this : key => parameter.name }
}

output "parameter_arns" {
  description = "Parameter ARNs for application IAM policies."
  value       = { for key, parameter in aws_ssm_parameter.this : key => parameter.arn }
}
