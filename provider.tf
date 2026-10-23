# Credentials and region come from the laptop's AWS environment/profile.
# Do not put access_key, secret_key, or session tokens in Terraform files.
provider "aws" {
  default_tags {
    tags = merge(var.tags, { ManagedBy = "Terraform" })
  }
}
