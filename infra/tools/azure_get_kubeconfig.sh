#!/bin/bash
set -e

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <environment_name>"
    echo "Example: $0 aks-managed"
    exit 1
fi

ENV_NAME="$1"

if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI ('az') is not installed. Please install it to continue."
    exit 1
fi

RESOURCE_GROUP="${ENV_NAME}-rg"
CLUSTER_NAME="${ENV_NAME}"
KUBECONFIG_DIR="../.kubeconfigs"
KUBECONFIG_FILE="${KUBECONFIG_DIR}/${ENV_NAME}-kubeconfig"

echo "Ensuring directory exists: ${KUBECONFIG_DIR}"
mkdir -p "$KUBECONFIG_DIR"

echo "Fetching kubeconfig for cluster '${CLUSTER_NAME}'..."
az aks get-credentials \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    --file "${KUBECONFIG_FILE}" \
    --overwrite-existing > /dev/null 

echo "Successfully generated kubeconfig: ${KUBECONFIG_FILE}"
echo ""
echo "To use this configuration, run:"
echo "export KUBECONFIG=\"$(realpath "${KUBECONFIG_FILE}")\""