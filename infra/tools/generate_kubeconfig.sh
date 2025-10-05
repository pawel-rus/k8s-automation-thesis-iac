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
KUBECONFIG_DIR="../.kubeconfigs"
KUBECONFIG_FILE="$KUBECONFIG_DIR/$ENV_NAME-kubeconfig"

# Check if Terraform output file exists
if [ ! -f "$TF_OUTPUT_FILE" ]; then
    echo "Error: File $TF_OUTPUT_FILE does not exist. Please run 'terraform output -json > tf_outputs.json' first."
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Install jq and try again."
    exit 1
fi

# Create target directory if it doesn't exist
mkdir -p "$KUBECONFIG_DIR"

# Retrieve kubeconfig content from JSON
KUBECONFIG_CONTENT=$(jq -r '.kubeconfig.value' "$TF_OUTPUT_FILE")

# Generate the kubeconfig file
echo "$KUBECONFIG_CONTENT" > "$KUBECONFIG_FILE"

echo "Kubeconfig generated successfully!"
echo "File path: $KUBECONFIG_FILE"

echo ""
echo "To use this kubeconfig file, set the KUBECONFIG environment variable:"
echo "export KUBECONFIG=$KUBECONFIG_FILE"