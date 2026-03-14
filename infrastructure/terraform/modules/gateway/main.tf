variable "project_name" { type = string }
variable "environment" { type = string }
variable "vpc_cidr" { type = string; default = "10.0.0.0/16" }
variable "azs" { type = list(string); default = ["us-east-1a", "us-east-1b"] }
data "aws_region" "current" {}

resource "aws_vpc" "main" { cidr_block = var.vpc_cidr; enable_dns_support = true; enable_dns_hostnames = true; tags = { Name = "${var.project_name}-${var.environment}-vpc" } }
resource "aws_subnet" "private" { count = length(var.azs); vpc_id = aws_vpc.main.id; cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index); availability_zone = var.azs[count.index]; tags = { Name = "${var.project_name}-${var.environment}-private-${count.index}" } }
resource "aws_subnet" "public" { count = length(var.azs); vpc_id = aws_vpc.main.id; cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index + 100); availability_zone = var.azs[count.index]; map_public_ip_on_launch = true; tags = { Name = "${var.project_name}-${var.environment}-public-${count.index}" } }
resource "aws_internet_gateway" "main" { vpc_id = aws_vpc.main.id }
resource "aws_eip" "nat" { domain = "vpc" }
resource "aws_nat_gateway" "main" { allocation_id = aws_eip.nat.id; subnet_id = aws_subnet.public[0].id }
resource "aws_route_table" "private" { vpc_id = aws_vpc.main.id; route { cidr_block = "0.0.0.0/0"; nat_gateway_id = aws_nat_gateway.main.id } }
resource "aws_route_table" "public" { vpc_id = aws_vpc.main.id; route { cidr_block = "0.0.0.0/0"; gateway_id = aws_internet_gateway.main.id } }
resource "aws_route_table_association" "private" { count = length(var.azs); subnet_id = aws_subnet.private[count.index].id; route_table_id = aws_route_table.private.id }
resource "aws_route_table_association" "public" { count = length(var.azs); subnet_id = aws_subnet.public[count.index].id; route_table_id = aws_route_table.public.id }
resource "aws_vpc_endpoint" "dynamodb" { vpc_id = aws_vpc.main.id; service_name = "com.amazonaws.${data.aws_region.current.name}.dynamodb"; vpc_endpoint_type = "Gateway"; route_table_ids = [aws_route_table.private.id] }
resource "aws_vpc_endpoint" "s3" { vpc_id = aws_vpc.main.id; service_name = "com.amazonaws.${data.aws_region.current.name}.s3"; vpc_endpoint_type = "Gateway"; route_table_ids = [aws_route_table.private.id] }

output "vpc_id" { value = aws_vpc.main.id }
output "private_subnet_ids" { value = aws_subnet.private[*].id }
output "public_subnet_ids" { value = aws_subnet.public[*].id }
