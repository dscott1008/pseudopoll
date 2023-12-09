resource "aws_api_gateway_request_validator" "vote" {
  name                  = "vote-validator"
  rest_api_id           = var.rest_api_id
  validate_request_body = true
}

resource "aws_api_gateway_method" "patch" {
  rest_api_id = var.rest_api_id
  http_method = "PATCH"
  resource_id = var.poll_resource_id

  authorization = "CUSTOM"
  authorizer_id = var.custom_authorizer_id

  request_validator_id = aws_api_gateway_request_validator.vote.id
  request_models = {
    "application/json" = var.vote_model_name
  }
}

resource "aws_api_gateway_integration" "vote" {
  rest_api_id             = var.rest_api_id
  resource_id             = var.poll_resource_id
  http_method             = aws_api_gateway_method.patch.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  passthrough_behavior    = "NEVER"
  credentials             = var.api_role_arn
  uri                     = "arn:aws:apigateway:${var.region}:sqs:path/${aws_sqs_queue.vote_queue.name}"

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = templatefile("${path.module}/../../templates/mappings/vote.vm", {})
  }
}

resource "aws_api_gateway_integration_response" "vote_accepted" {
  rest_api_id       = var.rest_api_id
  resource_id       = var.poll_resource_id
  http_method       = aws_api_gateway_method.patch.http_method
  status_code       = aws_api_gateway_method_response.patch_accepted.status_code
  selection_pattern = "^2[0-9][0-9]"

  response_templates = {
    "application/json" = "{\"message\": \"Vote queued.\"}"
  }
}

resource "aws_api_gateway_method_response" "patch_accepted" {
  rest_api_id = var.rest_api_id
  resource_id = var.poll_resource_id
  http_method = aws_api_gateway_method.patch.http_method
  status_code = "202"
}

resource "aws_api_gateway_method" "public_patch" {
  rest_api_id = var.rest_api_id
  http_method = "PATCH"
  resource_id = var.public_poll_resource_id

  authorization = "NONE"

  request_validator_id = aws_api_gateway_request_validator.vote.id
  request_models = {
    "application/json" = var.vote_model_name
  }
}

resource "aws_api_gateway_integration" "public_vote" {
  rest_api_id             = var.rest_api_id
  resource_id             = var.public_poll_resource_id
  http_method             = aws_api_gateway_method.public_patch.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  passthrough_behavior    = "WHEN_NO_TEMPLATES"
  credentials             = var.api_role_arn
  uri                     = "arn:aws:apigateway:${var.region}:sqs:path/${aws_sqs_queue.vote_queue.name}"

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = templatefile("${path.module}/../../templates/mappings/vote.vm", {})
  }
}

resource "aws_api_gateway_integration_response" "public_vote_accepted" {
  rest_api_id       = var.rest_api_id
  resource_id       = var.public_poll_resource_id
  http_method       = aws_api_gateway_method.public_patch.http_method
  status_code       = aws_api_gateway_method_response.public_patch_accepted.status_code
  selection_pattern = "^2[0-9][0-9]"

  response_templates = {
    "application/json" = "{\"message\": \"Vote queued.\"}"
  }
}

resource "aws_api_gateway_method_response" "public_patch_accepted" {
  rest_api_id = var.rest_api_id
  resource_id = var.public_poll_resource_id
  http_method = aws_api_gateway_method.public_patch.http_method
  status_code = "202"
}

module "api_queue_iam" {
  source         = "./iam"
  api_role_name  = var.api_role_name
  vote_queue_arn = aws_sqs_queue.vote_queue.arn
}

resource "aws_sqs_queue" "vote_queue" {
  name = "pseudopoll-vote-queue"
}

resource "aws_sqs_queue_redrive_policy" "vote_queue" {
  queue_url = aws_sqs_queue.vote_queue.id
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.vote_queue_dead_letter.arn,
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue" "vote_queue_dead_letter" {
  name = "pseudopoll-vote-queue-dead-letter"
}

resource "aws_lambda_event_source_mapping" "vote" {
  event_source_arn = aws_sqs_queue.vote_queue.arn
  function_name    = module.vote_lambda.arn
}

module "vote_lambda_role" {
  source    = "../../lambda/iam"
  role_name = "pseudopoll-vote-lambda-role"
}

resource "aws_iam_role_policy_attachment" "vote_logging" {
  role       = module.vote_lambda_role.role_name
  policy_arn = var.lambda_logging_policy_arn
}

data "aws_iam_policy_document" "vote_lambda_sqs" {
  statement {
    effect = "Allow"

    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]

    resources = [aws_sqs_queue.vote_queue.arn]
  }
}

resource "aws_iam_policy" "vote_lambda_sqs" {
  name        = "pseudopoll-vote-lambda-sqs"
  description = "IAM policy for the vote lambda to receive messages from the vote queue"
  path        = "/"
  policy      = data.aws_iam_policy_document.vote_lambda_sqs.json
}

resource "aws_iam_role_policy_attachment" "vote_lambda_sqs" {
  role       = module.vote_lambda_role.role_name
  policy_arn = aws_iam_policy.vote_lambda_sqs.arn
}

module "vote_lambda" {
  source              = "../../lambda"
  function_name       = "pseudopoll-vote"
  role_arn            = module.vote_lambda_role.role_arn
  archive_source_file = "${path.module}/../../../../backend/lambdas/vote/bin/bootstrap"
  archive_output_path = "${path.module}/../../../../backend/lambdas/vote/bin/vote.zip"
}