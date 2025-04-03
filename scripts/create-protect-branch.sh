#!/bin/bash

# Get organization name and GitHub token from arguments
ORG_NAME="$1"
GITHUB_TOKEN="$2"
shift 2
REPO_NAMES=("$@") # Remaining arguments are repo names

# Validate required parameters
if [ -z "$ORG_NAME" ] || [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: Organization name and GitHub token are required."
    echo "Usage: $0 <org-name> <github-token> [repo1 repo2 ...]"
    exit 1
fi

# Authenticate GitHub CLI using the GITHUB_TOKEN
echo "$GITHUB_TOKEN" | gh auth login --with-token

# If no repo names are provided, fetch all repositories from the organization
if [ ${#REPO_NAMES[@]} -eq 0 ]; then
    echo "Fetching repositories from organization: $ORG_NAME..."
    REPO_NAMES=($(gh repo list "$ORG_NAME" --limit 100 --json name --jq '.[].name' 2>/dev/null))

    if [ ${#REPO_NAMES[@]} -eq 0 ]; then
        echo "No repositories found in organization $ORG_NAME."
        exit 0
    fi
fi

# Loop through all the repositories
for repo in "${REPO_NAMES[@]}"; do
    echo "Processing repository: $repo"

    # Check if the repository exists
    if ! gh api repos/$ORG_NAME/$repo &>/dev/null; then
        echo "Warning: Repository $ORG_NAME/$repo does not exist or access is denied. Skipping."
        continue
    fi

    # Get the default branch of the repository
    DEFAULT_BRANCH=$(gh api repos/$ORG_NAME/$repo --jq '.default_branch')
    echo "Default branch of $repo is $DEFAULT_BRANCH"

    # Create 'main' branch if it doesn't exist
    if ! gh api repos/$ORG_NAME/$repo/branches/main &>/dev/null; then
        echo "Creating 'main' branch in $repo..."
        gh api -X POST repos/$ORG_NAME/$repo/git/refs -f ref="refs/heads/main" -f sha="$(gh api repos/$ORG_NAME/$repo/git/ref/heads/$DEFAULT_BRANCH --jq '.object.sha')" || {
            echo "Error: Failed to create 'main' branch for $repo"
            continue
        }
    else
        echo "'main' branch already exists in $repo."
    fi

    # Create 'dev' branch if it doesn't exist
    if ! gh api repos/$ORG_NAME/$repo/branches/dev &>/dev/null; then
        echo "Creating 'dev' branch in $repo..."
        gh api -X POST repos/$ORG_NAME/$repo/git/refs -f ref="refs/heads/dev" -f sha="$(gh api repos/$ORG_NAME/$repo/git/ref/heads/main --jq '.object.sha')" || {
            echo "Error: Failed to create 'dev' branch for $repo"
            continue
        }
    else
        echo "'dev' branch already exists in $repo."
    fi

    # Set 'dev' as the default branch
    echo "Setting 'dev' as the default branch for $repo..."
    gh repo edit "$ORG_NAME/$repo" --default-branch dev || {
        echo "Warning: Failed to set 'dev' as default branch for $repo."
    }

    echo "Completed processing $repo."
    echo "---------------------------------"
done

echo "All repositories processed successfully!"
