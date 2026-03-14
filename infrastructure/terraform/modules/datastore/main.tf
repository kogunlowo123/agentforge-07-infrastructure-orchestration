variable "project_name" { type = string }
variable "environment" { type = string }

resource "aws_kms_key" "data" { description = "${var.project_name}-${var.environment} encryption"; enable_key_rotation = true }
resource "aws_kms_alias" "data" { name = "alias/${var.project_name}-${var.environment}"; target_key_id = aws_kms_key.data.key_id }

resource "aws_dynamodb_table" "sessions" {
  name = "${var.project_name}-${var.environment}-sessions"; billing_mode = "PAY_PER_REQUEST"
  hash_key = "sessionId"; range_key = "timestamp"
  attribute { name = "sessionId"; type = "S" }
  attribute { name = "timestamp"; type = "N" }
  ttl { attribute_name = "ttl"; enabled = true }
  server_side_encryption { enabled = true; kms_key_arn = aws_kms_key.data.arn }
  point_in_time_recovery { enabled = true }
}

resource "aws_s3_bucket" "knowledge" { bucket = "${var.project_name}-${var.environment}-knowledge" }
resource "aws_s3_bucket_versioning" "knowledge" { bucket = aws_s3_bucket.knowledge.id; versioning_configuration { status = "Enabled" } }
resource "aws_s3_bucket_server_side_encryption_configuration" "knowledge" { bucket = aws_s3_bucket.knowledge.id; rule { apply_server_side_encryption_by_default { sse_algorithm = "aws:kms"; kms_master_key_id = aws_kms_key.data.arn } } }
resource "aws_s3_bucket_public_access_block" "knowledge" { bucket = aws_s3_bucket.knowledge.id; block_public_acls = true; block_public_policy = true; ignore_public_acls = true; restrict_public_buckets = true }

output "sessions_table_name" { value = aws_dynamodb_table.sessions.name }
output "sessions_table_arn" { value = aws_dynamodb_table.sessions.arn }
output "knowledge_bucket" { value = aws_s3_bucket.knowledge.id }
output "kms_key_arn" { value = aws_kms_key.data.arn }
