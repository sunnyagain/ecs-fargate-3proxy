output "start_socks5_url" {
  value       = "${aws_api_gateway_deployment.socks5_api.invoke_url}/start"
  description = "The URL to start the SOCKS5 server."
}

output "stop_socks5_url" {
  value       = "${aws_api_gateway_deployment.socks5_api.invoke_url}/stop"
  description = "The URL to stop the SOCKS5 server."
}
