terraform {
  required_version = ">= 1.6.0"
  required_providers { aws = { source = "hashicorp/aws"; version = "~> 5.0" } }
}
provider "aws" { region = var.aws_region }
variable "aws_region" { type = string; default = "us-east-1" }

module "gateway"   { source = "../../modules/gateway";   project_name = "agentforge-07"; environment = "dev" }
module "datastore" { source = "../../modules/datastore"; project_name = "agentforge-07"; environment = "dev" }
module "runtime"   { source = "../../modules/runtime";   project_name = "agentforge-07"; environment = "dev" }

output "api_endpoint"    { value = module.runtime.api_endpoint }
output "sessions_table"  { value = module.datastore.sessions_table_name }
