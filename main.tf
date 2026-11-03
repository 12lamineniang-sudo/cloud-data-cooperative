terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

variable "aws_region" {
  description = "Région AWS pour le déploiement local"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Environnement (dev, test, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Nom de la coopérative de données"
  type        = string
  default     = "data-cooperative"
}

# -----------------------------------------------------------------------------
# PROVIDER AWS ORIENTÉ LOCALSTACK (COMMUNITY 100% GRATUIT)
# -----------------------------------------------------------------------------
provider "aws" {
  region                      = var.aws_region
  access_key                  = "mock_access_key"
  secret_key                  = "mock_secret_key"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    apigateway = "http://localhost:4566"
    dynamodb   = "http://localhost:4566"
    iam        = "http://localhost:4566"
    lambda     = "http://localhost:4566"
    s3         = "http://localhost:4566"
  }
}

# -----------------------------------------------------------------------------
# 1. TABLE DE CORRESPONDANCE DYNAMODB (DEVICE MAPPING)
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "device_mapping" {
  name         = "${var.project_name}-device-mapping-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "device_token"

  attribute {
    name = "device_token"
    type = "S"
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_dynamodb_table_item" "sample_sabra_device" {
  table_name = aws_dynamodb_table.device_mapping.name
  hash_key   = aws_dynamodb_table.device_mapping.hash_key

  item = jsonencode({
    device_token = { S = "token_sabra_01" }
    device_id    = { S = "station_bruit_sabra_01" }
    department   = { S = "sabra" }
    is_active    = { BOOL = true }
  })
}

resource "aws_dynamodb_table_item" "sample_ocba_device" {
  table_name = aws_dynamodb_table.device_mapping.name
  hash_key   = aws_dynamodb_table.device_mapping.hash_key

  item = jsonencode({
    device_token = { S = "token_ocba_01" }
    device_id    = { S = "clemap_energie_ocba_01" }
    department   = { S = "ocba" }
    is_active    = { BOOL = true }
  })
}

resource "aws_dynamodb_table_item" "sample_oceau_device" {
  table_name = aws_dynamodb_table.device_mapping.name
  hash_key   = aws_dynamodb_table.device_mapping.hash_key

  item = jsonencode({
    device_token = { S = "token_oceau_01" }
    device_id    = { S = "station_pluvio_oceau_01" }
    department   = { S = "oceau" }
    is_active    = { BOOL = true }
  })
}

# -----------------------------------------------------------------------------
# 2. STOCKAGE S3 DÉPARTEMENTAL (DATA STORES - CSV & JSON)
# -----------------------------------------------------------------------------
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "data_store" {
  bucket        = "${var.project_name}-store-${var.environment}-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# 3. RÔLE ET POLITIQUES IAM POUR LA LAMBDA
# -----------------------------------------------------------------------------
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_pipeline_policy" {
  name        = "${var.project_name}-pipeline-policy-${var.environment}"
  description = "Autorisations DynamoDB et S3 pour le pipeline d'ingestion"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:Query"]
        Resource = aws_dynamodb_table.device_mapping.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.data_store.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_pipeline" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_pipeline_policy.arn
}

# -----------------------------------------------------------------------------
# 4. CODE LAMBDA EN PYTHON (GESTION DES FICHIERS CSV & JSON)
# -----------------------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/ingestion_pipeline.zip"

  source {
    content  = <<EOF
import json
import os
import time
import base64
import boto3
from datetime import datetime, timezone

# Endpoints pour LocalStack
localstack_host = os.environ.get('LOCALSTACK_HOSTNAME', 'localhost')
endpoint_url = f"http://{localstack_host}:4566"

dynamodb = boto3.resource('dynamodb', endpoint_url=endpoint_url)
s3 = boto3.client('s3', endpoint_url=endpoint_url)

MAPPING_TABLE = os.environ.get('MAPPING_TABLE')
DATA_STORE_BUCKET = os.environ.get('DATA_STORE_BUCKET')

def get_header_case_insensitive(headers, key):
    if not headers:
        return None
    for k, v in headers.items():
        if k.lower() == key.lower():
            return v
    return None

def lambda_handler(event, context):
    device_token = None
    content_type = "application/json"
    body_content = ""
    is_http = False

    if "headers" in event:
        is_http = True
        headers = event.get("headers", {})
        device_token = get_header_case_insensitive(headers, "device_token")
        content_type = get_header_case_insensitive(headers, "content-type") or "text/csv"
        
        raw_body = event.get("body", "")
        if event.get("isBase64Encoded", False):
            body_content = base64.b64decode(raw_body).decode('utf-8', errors='ignore')
        else:
            body_content = raw_body
    else:
        device_token = event.get("device_token")
        body_content = json.dumps(event.get("payload", event))

    if not device_token:
        if is_http:
            return {
                "statusCode": 401,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "Unauthorized", "message": "En-tête device_token manquant"})
            }
        return {"status": "rejected", "reason": "device_token manquant"}

    table = dynamodb.Table(MAPPING_TABLE)
    db_response = table.get_item(Key={"device_token": device_token})
    item = db_response.get("Item")

    if not item or not item.get("is_active", True):
        if is_http:
            return {
                "statusCode": 401,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "Unauthorized", "message": "Jeton d'appareil invalide ou non enregistré"})
            }
        return {"status": "rejected", "reason": "Jeton invalide"}

    department = item.get("department", "inconnu")
    device_id = item.get("device_id", "appareil_inconnu")

    now_utc = datetime.now(timezone.utc)
    date_path = now_utc.strftime('%Y/%m/%d')
    epoch_now = int(time.time())

    is_csv = "csv" in content_type.lower() or body_content.strip().startswith(("Station", "timestamp", "date", "Time", "sensor", "device"))
    ext = "csv" if is_csv else "json"
    s3_key = f"{department}/{date_path}/{epoch_now}_{device_id}.{ext}"

    s3.put_object(
        Bucket=DATA_STORE_BUCKET,
        Key=s3_key,
        Body=body_content,
        ContentType="text/csv" if is_csv else "application/json",
        Metadata={
            "device_id": device_id,
            "department": department,
            "ingested_at": now_utc.isoformat()
        }
    )

    result = {
        "status": "success",
        "message": f"Fichier {ext.upper()} accepté et stocké pour le département '{department}'",
        "device_id": device_id,
        "department": department,
        "s3_path": f"s3://{DATA_STORE_BUCKET}/{s3_key}"
    }

    if is_http:
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(result)
        }
    return result
EOF
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "ingestion_pipeline" {
  function_name    = "${var.project_name}-ingestion-pipeline-${var.environment}"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 256

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      MAPPING_TABLE     = aws_dynamodb_table.device_mapping.name
      DATA_STORE_BUCKET = aws_s3_bucket.data_store.id
    }
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# 5. INTEGRATION HTTP (API GATEWAY V1 - REST API 100% GRATUIT SUR LOCALSTACK)
# -----------------------------------------------------------------------------
resource "aws_api_gateway_rest_api" "http_api" {
  name        = "${var.project_name}-http-endpoint-${var.environment}"
  description = "API REST d'ingestion pour LocalStack"
}

resource "aws_api_gateway_resource" "ingest_resource" {
  rest_api_id = aws_api_gateway_rest_api.http_api.id
  parent_id   = aws_api_gateway_rest_api.http_api.root_resource_id
  path_part   = "ingest"
}

resource "aws_api_gateway_method" "ingest_method" {
  rest_api_id   = aws_api_gateway_rest_api.http_api.id
  resource_id   = aws_api_gateway_resource.ingest_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.http_api.id
  resource_id             = aws_api_gateway_resource.ingest_resource.id
  http_method             = aws_api_gateway_method.ingest_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.ingestion_pipeline.invoke_arn
}

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on  = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.http_api.id
  stage_name  = "dev"
}

resource "aws_lambda_permission" "api_gw_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestion_pipeline.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.http_api.execution_arn}/*/*/*"
}

# -----------------------------------------------------------------------------
# OUTPUTS
# -----------------------------------------------------------------------------
output "http_ingest_url" {
  description = "URL d'ingestion HTTP LocalStack (REST API v1)"
  value       = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.http_api.id}/dev/_user_request_/ingest"
}

output "s3_bucket_name" {
  description = "Nom du bucket S3 servant de Data Store"
  value       = aws_s3_bucket.data_store.id
}
