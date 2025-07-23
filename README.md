# Kubernetes Automation Thesis

**Automating Kubernetes environments in public cloud**

> Analysis of management, performance, scalability, cost and deployment complexity of provider‑managed vs. self‑managed clusters.

---

## 📖 Purpose

This repository contains all Infrastructure as Code and automation artifacts for my engineering thesis:

> **"Automating Kubernetes environments in public cloud – analysis of management, performance, scalability, cost and deployment complexity of provider‑managed vs. self‑managed clusters."**

* **Terraform** modules for AWS EKS, Azure AKS and self‑managed VM clusters
* **Ansible** playbooks for cluster bootstrap and Day‑2 operations
* **Helm** charts and overrides
* **CI/CD** pipelines (Jenkinsfiles & GitHub Actions workflows)

## 🚀 Structure

```
├── terraform/
│   ├── eks/          # EKS modules and examples
│   └── self-managed/ # VM-based Kubernetes modules
├── ansible/
│   └── playbooks/    # Ansible roles and playbooks
├── helm/
│   └── charts/       # Custom Helm charts
├── ci-cd/
│   ├── jenkins/      # Jenkins pipelines
│   └── github-actions/ # GitHub Actions workflows
└── docs/             # Design docs, cost analysis, benchmarks
```
