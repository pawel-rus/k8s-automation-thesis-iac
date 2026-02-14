#!/bin/bash
set -e

# === Usage check ===
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <environment_name>"
  exit 1
fi

ENV_NAME="$1"

# === Paths ===
TF_OUTPUT_FILE="../terraform/envs/$ENV_NAME/tf_outputs.json"
KUBECONFIG_PATH="../.kubeconfigs/${ENV_NAME}-kubeconfig"

echo "=== Setting KUBECONFIG path ==="
export KUBECONFIG="$KUBECONFIG_PATH"
echo "Using kubeconfig: $KUBECONFIG"

# === Check if Terraform outputs exist ===
if [ ! -f "$TF_OUTPUT_FILE" ]; then
  echo "Terraform outputs not found: $TF_OUTPUT_FILE"
  echo "Run 'terraform output -json > tf_outputs.json' in the environment directory first."
  exit 1
fi

# === Check dependencies ===
if ! command -v jq &> /dev/null; then
  echo "Missing dependency: jq"
  exit 1
fi
if ! command -v aws &> /dev/null; then
  echo "Missing dependency: aws CLI"
  exit 1
fi
if ! command -v kubectl &> /dev/null; then
  echo "Missing dependency: kubectl"
  exit 1
fi

# === Helper: convert private IP -> node name ===
to_node_name() {
  local ip="$1"
  echo "ip-${ip//./-}"
}

# === Read Terraform outputs ===
echo "=== Reading Terraform outputs ==="
MASTER_ID=$(jq -r '.master_instance_id.value' "$TF_OUTPUT_FILE")
MASTER_PRIVATE_IP=$(jq -r '.master_private_ip.value' "$TF_OUTPUT_FILE")
WORKER_IDS=($(jq -r '.worker_instance_ids.value[]' "$TF_OUTPUT_FILE"))
WORKER_IPS=($(jq -r '.worker_private_ips.value[]' "$TF_OUTPUT_FILE"))

# === Fetch Availability Zones ===
echo "=== Fetching Availability Zones for instances ==="
MASTER_AZ=$(aws ec2 describe-instances \
  --instance-ids "$MASTER_ID" \
  --query "Reservations[0].Instances[0].Placement.AvailabilityZone" \
  --output text)

WORKER_AZS=()
for id in "${WORKER_IDS[@]}"; do
  az=$(aws ec2 describe-instances \
    --instance-ids "$id" \
    --query "Reservations[0].Instances[0].Placement.AvailabilityZone" \
    --output text)
  WORKER_AZS+=("$az")
done

# === Patch master node ===
echo "=== Patching master node ==="
MASTER_NODE_NAME=$(to_node_name "$MASTER_PRIVATE_IP")
echo "Patching $MASTER_NODE_NAME -> $MASTER_ID ($MASTER_AZ)"
kubectl patch node "$MASTER_NODE_NAME" -p "{\"spec\":{\"providerID\":\"aws:///$MASTER_AZ/$MASTER_ID\"}}" || true

# === Patch worker nodes ===
echo "=== Patching worker nodes ==="
for i in "${!WORKER_IDS[@]}"; do
  worker_id="${WORKER_IDS[$i]}"
  worker_ip="${WORKER_IPS[$i]}"
  worker_az="${WORKER_AZS[$i]}"
  worker_node_name=$(to_node_name "$worker_ip")

  echo "Patching $worker_node_name -> $worker_id ($worker_az)"
  kubectl patch node "$worker_node_name" -p "{\"spec\":{\"providerID\":\"aws:///$worker_az/$worker_id\"}}" || true
done

echo "All nodes patched successfully."
