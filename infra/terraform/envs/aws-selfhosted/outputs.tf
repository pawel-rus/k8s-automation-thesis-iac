output "public_ips" {
  value = aws_instance.nodes[*].public_ip
}

output "private_ips" {
  value = aws_instance.nodes[*].private_ip
}
