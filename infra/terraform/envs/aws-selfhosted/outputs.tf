output "master_instance_id" {
  description = "EC2 instance ID of the master node, for SSM access."
  value       = aws_instance.master.id
}

output "master_public_ip" {
  description = "Public IP address of the Kubernetes master node for kubectl access."
  value       = aws_instance.master.public_ip
}

output "master_private_ip" {
  description = "Private IP address of the Kubernetes master node"
  value       = aws_instance.master.private_ip
}

output "worker_instance_ids" {
  description = "EC2 instance IDs of the worker nodes, for SSM access."
  value       = aws_instance.workers[*].id
}

output "worker_private_ips" {
  description = "Private IP addresses of the Kubernetes worker nodes"
  value       = aws_instance.workers[*].private_ip
}
