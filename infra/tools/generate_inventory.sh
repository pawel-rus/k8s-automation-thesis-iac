#!/bin/bash
set -e

# Check arguments
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <environment_name>"
  exit 1
fi

ENV_NAME="$1"

# Paths
TF_OUTPUT_FILE="../terraform/envs/$ENV_NAME/tf_outputs.json"
INVENTORY_DIR="../ansible/environments"
INVENTORY_FILE="$INVENTORY_DIR/$ENV_NAME.yaml"

# Check if Terraform output file exists
if [ ! -f "$TF_OUTPUT_FILE" ]; then
  echo "File $TF_OUTPUT_FILE does not exist."
  exit 1
fi

# Create target directory if it doesn't exist
mkdir -p "$INVENTORY_DIR"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo "jq is not installed. Install jq and try again."
  exit 1
fi

# Retrieve IPs from JSON
MASTER_IP=$(jq -r '.master_public_ip.value' "$TF_OUTPUT_FILE")
WORKER_IPS=($(jq -r '.worker_public_ips.value[]' "$TF_OUTPUT_FILE"))

# Generate YAML inventory
{
echo "all:"
echo "  hosts:"
echo "    master:"
echo "      ansible_host: $MASTER_IP"
for i in "${!WORKER_IPS[@]}"; do
  index=$((i+1))
  echo "    worker$index:"
  echo "      ansible_host: ${WORKER_IPS[i]}"
done
echo "  vars:"
echo "    master_node_ip: $MASTER_IP"
echo "    access_user: ubuntu"
echo "    project_name: k8s-automation-thesis"
echo "    project_env: $ENV_NAME"
echo "  children:"
echo "    kube_control_plane:"
echo "      hosts:"
echo "        master:"
echo "    kube_node:"
echo "      hosts:"
for i in "${!WORKER_IPS[@]}"; do
  index=$((i+1))
  echo "        worker$index:"
done
echo "    k8s_cluster:"
echo "      children:"
echo "        kube_control_plane:"
echo "        kube_node:"
} > "$INVENTORY_FILE"

echo "Inventory generated in file $INVENTORY_FILE"

# Add master and worker hosts to known_hosts to avoid SSH key confirmation
echo "Adding hosts to ~/.ssh/known_hosts to avoid SSH key confirmation..."
ssh-keyscan -H "$MASTER_IP" >> ~/.ssh/known_hosts 2>/dev/null
for ip in "${WORKER_IPS[@]}"; do
  ssh-keyscan -H "$ip" >> ~/.ssh/known_hosts 2>/dev/null
done
echo "Hosts added to known_hosts successfully."
