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
  echo "Run 'terraform output -json > tf_outputs.json' in the correct directory first."
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
MASTER_ID=$(jq -r '.master_instance_id.value' "$TF_OUTPUT_FILE")
MASTER_IP=$(jq -r '.master_public_ip.value' "$TF_OUTPUT_FILE")
MASTER_PRIVATE_IP=$(jq -r '.master_private_ip.value' "$TF_OUTPUT_FILE")
WORKER_IDS=($(jq -r '.worker_instance_ids.value[]' "$TF_OUTPUT_FILE"))

# Generate YAML inventory
cat << EOF > "$INVENTORY_FILE"
all:
  vars:
    master_node_ip: $MASTER_PRIVATE_IP
    master_public_ip: $MASTER_IP
    access_user: ubuntu 
    ansible_user: ubuntu
    project_name: k8s-automation-thesis
    project_env: $ENV_NAME

  children:
    kube_control_plane:
      hosts:
        master:
          ansible_host: $MASTER_ID

    kube_node:
      hosts:
EOF

# Append worker nodes to the 'kube_node' group in the YAML file
for i in "${!WORKER_IDS[@]}"; do
  index=$((i+1))
  cat << EOF >> "$INVENTORY_FILE"
        worker$index:
          ansible_host: ${WORKER_IDS[i]}
EOF
done

# Append the final cluster group definitions
cat << EOF >> "$INVENTORY_FILE"

    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
EOF

echo "Inventory generated in file $INVENTORY_FILE"

# Add master and worker hosts to known_hosts to avoid SSH key confirmation
echo "Adding hosts to ~/.ssh/known_hosts to avoid SSH key confirmation..."
ssh-keyscan -H "$MASTER_IP" >> ~/.ssh/known_hosts 2>/dev/null
for ip in "${WORKER_IPS[@]}"; do
  ssh-keyscan -H "$ip" >> ~/.ssh/known_hosts 2>/dev/null
done
echo "Hosts added to known_hosts successfully."
