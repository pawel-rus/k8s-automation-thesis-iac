output "master_public_ip" {
  description = "Public IP address of the Kubernetes master node"
  value       = aws_instance.master.public_ip
}

output "master_private_ip" {
  description = "Private IP address of the Kubernetes master node"
  value       = aws_instance.master.private_ip
}

output "worker_public_ips" {
  description = "Public IP addresses of the Kubernetes worker nodes"
  value       = aws_instance.workers[*].public_ip
}

output "worker_private_ips" {
  description = "Private IP addresses of the Kubernetes worker nodes"
  value       = aws_instance.workers[*].private_ip
}
