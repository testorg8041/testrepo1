#!/bin/bash

# Check if organization name is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <organization_name> [repo_name1 repo_name2 ...]"
    exit 1
fi

ORG_NAME="$1"
shift
REPO_NAMES=("$@")

echo "Updating branches for organization: $ORG_NAME"
echo "Repositories specified: ${#REPO_NAMES[@]}"

# Call the create-protect-branch.sh script
"./scripts/create-protect-branch.sh" "$ORG_NAME" "${REPO_NAMES[@]}"

echo "Branch update completed!"