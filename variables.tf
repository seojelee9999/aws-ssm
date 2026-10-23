variable "parameter_prefix" {
  description = "SSM path prefix, for example /myapp/dev (no trailing slash)."
  type        = string
  nullable    = false

  validation {
    condition = (
      can(regex("^/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$", var.parameter_prefix)) &&
      !can(regex("(?i)^/(aws|ssm)", var.parameter_prefix)) &&
      length(split("/", trim(var.parameter_prefix, "/"))) <= 14
    )
    error_message = "Use a leading slash, valid path segments, at most 14 prefix levels, and no reserved aws/ssm prefix."
  }
}

variable "parameters" {
  description = "Non-secret metadata keyed by environment variable name. Increment value_version when changing a value or parameter settings."
  type = map(object({
    type          = optional(string, "SecureString")
    description   = optional(string, "Managed by Terraform")
    value_version = optional(number, 1)
    key_id        = optional(string)
  }))
  nullable = false

  validation {
    condition     = length(var.parameters) > 0 && alltrue([for name in keys(var.parameters) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", name))])
    error_message = "Define at least one parameter using valid environment variable names."
  }

  validation {
    condition     = alltrue([for p in var.parameters : contains(["String", "StringList", "SecureString"], p.type)])
    error_message = "Parameter type must be String, StringList, or SecureString."
  }

  validation {
    condition     = alltrue([for p in var.parameters : p.value_version >= 1 && floor(p.value_version) == p.value_version])
    error_message = "value_version must be a positive integer."
  }

  validation {
    condition     = alltrue([for p in var.parameters : p.key_id == null || p.type == "SecureString"])
    error_message = "key_id is only supported for SecureString parameters."
  }
}

variable "parameter_values" {
  description = "Parameter values supplied through TF_VAR_parameter_values as a JSON object. Never save in tfvars."
  type        = map(string)
  sensitive   = true
  ephemeral   = true
  nullable    = false

  validation {
    condition     = toset(keys(var.parameter_values)) == toset(keys(var.parameters))
    error_message = "parameter_values must contain exactly the keys defined in parameters."
  }

  validation {
    condition     = alltrue([for value in values(var.parameter_values) : try(length(value) > 0, false)])
    error_message = "Parameter values must not be null or empty."
  }
}

variable "tags" {
  description = "Non-secret tags for all parameters."
  type        = map(string)
  default     = {}
  nullable    = false
}
