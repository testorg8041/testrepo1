#!/bin/bash

# Get Organization Name and PAT Token from arguments
ORG_NAME=$1
TOKEN=$2

# Validate inputs
if [[ -z "$ORG_NAME" || -z "$TOKEN" ]]; then
  echo "Error: Organization name and PAT token are required."
  echo "Usage: scripts/create-protect-branch.sh <org-name> <pat-token> [repo1 repo2 ...]"
  exit 1
fi

# Authenticate GitHub CLI using PAT
echo $TOKEN | gh auth login --with-token

# Fetch all repositories in the organization
echo "Fetching repositories from organization: $ORG_NAME..."
REPOS=$(gh repo list $ORG_NAME --limit 100 --json name --jq '.[].name')

# Loop through each repository
for REPO in $REPOS; do
  echo "Processing repository: $REPO"

  # Get the default branch of the repository
  DEFAULT_BRANCH=$(gh repo view "$ORG_NAME/$REPO" --json defaultBranchRef --jq '.defaultBranchRef.name')
  echo "Default branch of $REPO is $DEFAULT_BRANCH"

  # Create 'main' branch if it doesn't exist
  if ! gh api repos/$ORG_NAME/$REPO/branches/main &>/dev/null; then
    echo "Creating 'main' branch in $REPO..."
    gh api repos/$ORG_NAME/$REPO/git/refs \
      -X POST \
      -f ref="refs/heads/main" \
      -f sha=$(gh api repos/$ORG_NAME/$REPO/git/ref/heads/$DEFAULT_BRANCH --jq '.object.sha')
  else
    echo "'main' branch already exists in $REPO."
  fi

  # Create 'dev' branch if it doesn't exist
  if ! gh api repos/$ORG_NAME/$REPO/branches/dev &>/dev/null; then
    echo "Creating 'dev' branch in $REPO..."
    gh api repos/$ORG_NAME/$REPO/git/refs \
      -X POST \
      -f ref="refs/heads/dev" \
      -f sha=$(gh api repos/$ORG_NAME/$REPO/git/ref/heads/$DEFAULT_BRANCH --jq '.object.sha')
  else
    echo "'dev' branch already exists in $REPO."
  fi

  # Set 'dev' as the default branch
  echo "Setting 'dev' as the default branch for $REPO..."
  RESPONSE=$(gh api repos/$ORG_NAME/$REPO \
    -X PATCH \
    -F default_branch="dev" 2>&1)

  if [[ $RESPONSE == *"Resource not accessible by integration"* ]]; then
    echo "Warning: Failed to set 'dev' as default branch for $REPO. Check permissions."
  else
    echo "'dev' branch is now the default branch for $REPO."
  fi

  echo "---------------------------------"
done

echo "All repositories processed successfully!"
