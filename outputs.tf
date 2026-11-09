output "api_url" {
  description = "URL ендпоінта GET /hello"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/hello"
}

output "local_api_url" {
  description = "URL для емулятора (формат LocalStack-сумісних емуляторів)"
  value       = "${coalesce(var.local_endpoint, "")}/restapis/${aws_api_gateway_rest_api.api.id}/prod/_user_request_/hello"
}