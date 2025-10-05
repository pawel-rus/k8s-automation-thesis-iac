output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster"
  value       = aws_eks_cluster.cluster.endpoint
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.cluster.name
}

output "kubeconfig" {
  description = "Kubectl configuration to connect to the EKS cluster"
  value       = <<-EOT
    apiVersion: v1
    clusters:
    - cluster:
        server: ${aws_eks_cluster.cluster.endpoint}
        certificate-authority-data: ${aws_eks_cluster.cluster.certificate_authority[0].data}
      name: kubernetes
    contexts:
    - context:
        cluster: kubernetes
        user: aws
      name: aws
    current-context: aws
    kind: Config
    users:
    - name: aws
      user:
        exec:
          apiVersion: client.authentication.k8s.io/v1beta1
          command: aws
          args:
            - "eks"
            - "get-token"
            - "--cluster-name"
            - "${aws_eks_cluster.cluster.name}"
          env: []
  EOT
}