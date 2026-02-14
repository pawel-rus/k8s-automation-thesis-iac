# Kubernetes Automation Thesis 

![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![Ansible](https://img.shields.io/badge/ansible-%231A1918.svg?style=for-the-badge&logo=ansible&logoColor=white)
![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)
![Helm](https://img.shields.io/badge/helm-%230F1689.svg?style=for-the-badge&logo=helm&logoColor=white)
![Helmfile](https://img.shields.io/badge/helmfile-%23004088.svg?style=for-the-badge&logo=helm&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Azure](https://img.shields.io/badge/azure-%230072C6.svg?style=for-the-badge&logo=microsoftazure&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/github%20actions-%232671E5.svg?style=for-the-badge&logo=githubactions&logoColor=white)
---

### **Thesis title:** Automation of Kubernetes Environments in the Public Cloud – Analysis of Management, Performance, Scalability, Costs, and Implementation Difficulty of Provider-Managed vs. Self-Managed Clusters.

##  Abstract

This repository contains the source code, Infrastructure as Code (IaC) definitions, and automation scripts developed for my engineering thesis. The project implements and compares three distinct Kubernetes environment models:

1. **Amazon Elastic Kubernetes Service** (Provider-Managed)
2. **Azure Kubernetes Service** (Provider-Managed)
3. **AWS Self-Managed** (custom k8s cluster on EC2 instances)

The codebase demonstrates a full lifecycle implementation, including infrastructure provisioning (Terraform), configuration management (Ansible), declarative application deployment (Helm & Helmfile), and performance testing (K6, Kube-burner).

---

## Project Structure

### 1. `infra/terraform/` (Infrastructure Layer)

Contains declarative definitions for cloud resources. The project uses a modular approach to provision resources in AWS and Azure.

* **`envs/`**: Entry points for specific environments.
* `eks-managed`: Provisions VPC, EKS Control Plane, Node Groups, and IAM roles.
* `aks-managed`: Provisions Resource Groups, VNet, and AKS Cluster with Managed Identity.
* `aws-selfhosted`: Provisions VPC, EC2 instances (Control Plane & Workers), Security Groups, and IAM roles necessary for a manual cluster bootstrap.

### 2. `infra/ansible/` (Configuration Layer)

Used exclusively for the **AWS Self-Managed** cluster to transform raw EC2 instances into a working Kubernetes cluster.

* **`manifests/`**: Static Kubernetes manifests applied during bootstrap (e.g., AWS Cloud Controller Manager, StorageClass gp2).
* **`roles/`**: Modular tasks handling specific configuration stages:
* `common`: OS preparation, disabling swap, installing `containerd`, `runc`, and CNI plugins.
* `control-plane`: Initializes the cluster using `kubeadm init`, configures `kubectl` for the admin.
* `join-cluster`: Joins worker nodes to the cluster.
* `configure-cloud-integration`: Patches nodes with AWS Provider IDs and installs the AWS CCM.
* `prometheus-crds-and-ebs-csi`: Prepares the cluster for monitoring and storage (EBS CSI Driver).

* **`requirements.yml`**: Dependencies for Ansible collections.

### 3. `src/` (Application Source)

A Python Flask web application developed to test the infrastructure capabilities.

* **`app/`**: Source code using `prometheus-client` to expose custom metrics (latency, request count) at `/metrics` and structured logging for Loki.
* **`Dockerfile`**: Multi-stage build definition for the application container.

### 4. `charts/` (Packaging)

* **`flask-app/`**: A custom Helm chart defining the deployment logic for the Python application.
* Includes templates for `Deployment`, `Service`, `Ingress`, `ServiceMonitor` (for Prometheus), and `HPA` (Horizontal Pod Autoscaler).

### 5. `helmfile/` (Deployment Orchestration)

Uses **Helmfile** to declaratively manage multiple Helm charts across different environments. This ensures the application stack is identical across EKS, AKS, and Self-Managed clusters.

* **`helmfile.yaml.gotmpl`**: The main entry point defining releases:
* `ingress-nginx`: Ingress Controller.
* `kube-prometheus-stack`: Prometheus & Grafana for monitoring.
* `loki-stack`: Log aggregation (Loki & Promtail).
* `flask-app`: The custom application.

* **`values/`**: Environment-specific overrides (e.g., specific domains or storage classes for `aws-selfhosted` vs `aks-managed`).
* **`dashboards/`**: JSON definitions for Grafana dashboards (App Overview, HPA Analysis) automatically imported during deployment.

### 6. `infra/tools/` (Utility Scripts)

Helper scripts that glue Terraform and Ansible together.

* **`generate_inventory.sh`**: Parses Terraform JSON outputs to dynamically generate the Ansible inventory file, mapping EC2 instance IDs to control-plane/worker groups.

### 7. `tests/` (Performance Analysis)


Scripts used to gather data for the thesis comparison.

* **`k6/`**: JavaScript load testing scripts to stress-test the application and trigger HPA scaling.
* **`kube-burner/`**: Go-based tool for checking control-plane latency and churn (pod creation time, service availability time).

### 8. `.github/workflows/` (CI/CD Automation)

Contains YAML definitions for automated pipelines triggered by GitHub Actions. This CI/CD setup manages the application lifecycle and infrastructure updates.

* **`New Application Version Release` (`release.yaml`)**: An end-to-end pipeline for safely releasing application updates. It runs security scans (SAST and DAST) , builds and pushes the Docker image to DockerHub , lints Helm and Helmfile configurations , and deploys the app to the selected environment.


* **`Security Scans` (`security-scan.yaml`)**: A standalone comprehensive security auditing workflow. It runs Semgrep SAST via a matrix strategy across Application, Helm, Ansible, and Terraform code , uses TruffleHog to scan the git history for leaked credentials , and runs OWASP ZAP for dynamic analysis. It packages all reports into a downloadable artifact.


* **`Deploy All Releases` (`deploy-all-releases.yaml`)**: A manually triggered workflow to deploy the full stack (Ingress, Monitoring, App) using Helmfile. It securely manages credentials using GitHub Secrets and environments.


---

##  Prerequisites

To replicate the environment, ensure the following tools are installed:

* **Terraform** (>= 1.5.0)
* **Ansible** (>= 2.10)
* **Kubectl**
* **Helm** & **Helmfile**
* **AWS CLI** & **Azure CLI**
* **Python 3** (for the web app and Ansible modules)

### Installation of dependencies

```bash
# Install Python Kubernetes module for Ansible
sudo apt install python3-kubernetes

# Install Helm
wget https://get.helm.sh/helm-v3.18.5-linux-amd64.tar.gz
tar -zxvf helm-v3.18.5-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/

# Install Helmfile
wget https://github.com/helmfile/helmfile/releases/download/v1.0.0/helmfile_1.1.9_linux_amd64.tar.gz # Check for latest version
tar -zxvf helmfile_1.1.9_linux_amd64.tar.gz
sudo mv helmfile /usr/local/bin/

```

---

##  Usage Workflow

The deployment follows the logical flow described in the thesis:

### 1. Infrastructure Provisioning (Terraform)

Navigate to the desired environment and apply the configuration.

```bash
cd infra/terraform/envs/aws-selfhosted
terraform init
terraform apply -auto-approve

```

### 2. Configuration (Ansible - Self-Managed Only)

For the AWS self-managed cluster, generate the inventory and run the playbook.

```bash
cd infra/tools
./generate_inventory.sh aws-selfhosted
cd infra/ansible
ansible-playbook -i environments/aws-selfhosted.yaml k8s-cluster.yaml

```

### 3. Service Deployment (Helmfile via GitHub Actions)

While Helmfile can be applied locally, the official deployment is fully automated through **GitHub Actions**. This ensures secure credential management via GitHub Secrets and consistent environment tracking.

Instead of running commands manually, you trigger the workflows directly from the GitHub Actions UI:

1. Navigate to the **Actions** tab in the repository.
2. Select the **Deploy All Releases** workflow from the left sidebar.
3. Click **Run workflow** and select your target `environment` (e.g., `aws-selfhosted`, `eks-managed`, `aks-managed`) and the cloud `provider` (e.g., `aws`, `azure`).
4. The pipeline will automatically configure your `kubeconfig`, install necessary dependencies (Helm, plugins, Helmfile), and apply the full stack to the active cluster using `helmfile apply`.



---

## Thesis Key Findings

1. **Deployment & Provisioning Time:** AKS was the fastest to reach operational readiness (~6 min). EKS took the longest (~17 min) due to the sequential installation of add-ons like AWS EBS CSI Driver and CloudWatch. The Self-Managed cluster remained highly competitive (~7 min) thanks to the combined automation of Terraform and Ansible.

2. **Performance & Autoscaling (k6):** Under simulated HTTP load, application response times and Horizontal Pod Autoscaler (HPA) triggers were virtually identical across all models when using equivalent compute resources. The deployment model does not bottleneck standard application request handling.

3. **Control Plane Stress (kube-burner):** While EKS had a lower median pod creation time (2000 ms) compared to the Self-Managed cluster (4000 ms) , EKS exhibited significantly higher tail latencies (P95/P99 up to 18000 ms) during massive pod churn. This was caused by the AWS VPC CNI communicating with the AWS API for IP allocation , whereas the Self-Managed cluster using Calico managed IP addressing locally with fewer latency spikes.

4. **Operational Overhead & Maintenance:** Managed services (EKS/AKS) drastically reduce administrative burdens by automating control plane maintenance, node updates, and scaling. The Self-Managed model offers full control but demands significantly higher engineering effort and custom automation for day-2 operations.

5. **Cost Efficiency:** Fixed monthly infrastructure costs for the tested AWS configurations were nearly identical. AKS proved to be the most cost-effective primarily due to cheaper networking components (no NAT Gateway requirement). However, the apparent savings of avoiding the EKS control plane fee in the Self-Managed model are quickly offset by hidden operational costs and maintenance time.

6. **Security Posture (kube-bench):** Provider-managed clusters inherently pass OS-level CIS Kubernetes Benchmarks out-of-the-box, as the provider secures the underlying node images. Conversely, the Self-Managed cluster fails basic OS-level tests (e.g., file permissions) by default, requiring immediate manual OS hardening by the administrator.

Ultimately, the thesis concludes that while Self-Managed clusters offer ultimate granular control, Managed Kubernetes (EKS/AKS) combined with strong IaC and CI/CD automation is the optimal choice for production environments, effectively balancing performance, security, and operational cost.

---
