#!/bin/bash

# Get organization name and GitHub token
ORG_NAME="$1"
PAT="$2"  # Use PAT instead of GITHUB_TOKEN
shift 2
REPO_NAMES=("$@") # Remaining arguments are treated as repo names

# Validate required parameters
if [ -z "$ORG_NAME" ] || [ -z "$PAT" ]; then
    echo "Error: Organization name and PAT token are required."
    echo "Usage: $0 <org-name> <pat-token> [repo1 repo2 ...]"
    exit 1
fi

# Authenticate Git CLI
echo "$PAT" | gh auth login --with-token

# Fetch repositories if none are provided
if [ ${#REPO_NAMES[@]} -eq 0 ]; then
    echo "Fetching repositories from organization: $ORG_NAME..."
    REPO_NAMES=($(gh repo list "$ORG_NAME" --limit 100 --json name --jq '.[].name'))
    
    if [ ${#REPO_NAMES[@]} -eq 0 ]; then
        echo "No repositories found in organization $ORG_NAME."
        exit 0
    fi
fi

# Store original directory
ORIGINAL_DIR=$(pwd)

for repo in "${REPO_NAMES[@]}"; do
    echo "Processing repository: $repo"

    # Clone the repository using PAT authentication
    if ! git clone "https://$PAT@github.com/$ORG_NAME/$repo.git" temp-repo --quiet; then
        echo "Error: Failed to clone repository $ORG_NAME/$repo"
        continue
    fi
    
    cd temp-repo || { echo "Error: Failed to change directory"; exit 1; }

    # Set Git identity
    git config user.email "github-actions@github.com"
    git config user.name "GitHub Actions"

    # Ensure 'main' branch exists
    if ! git rev-parse --verify main &>/dev/null; then
        echo "Creating 'main' branch..."
        git checkout --orphan main
        echo "# $repo" > README.md
        git add README.md
        git commit -m "Initialize main branch"
        git push origin main
    fi

    # Ensure 'dev' branch exists
    if ! git rev-parse --verify dev &>/dev/null; then
        echo "Creating 'dev' branch..."
        git checkout -b dev
        git push origin dev
    fi

    # Set default branch to 'dev'
    gh repo edit "$ORG_NAME/$repo" --default-branch dev || echo "Failed to set 'dev' as default branch"

    # Apply branch protection using PAT
    echo "Applying branch protection..."
    gh api --method PUT repos/$ORG_NAME/$repo/branches/main/protection \
        -f required_status_checks='null' \
        -f enforce_admins=true \
        -f required_pull_request_reviews='{"required_approving_review_count":1}' \
        -f restrictions='null' || echo "Failed to protect 'main' branch"

    gh api --method PUT repos/$ORG_NAME/$repo/branches/dev/protection \
        -f required_status_checks='null' \
        -f enforce_admins=true \
        -f required_pull_request_reviews='{"required_approving_review_count":1}' \
        -f restrictions='null' || echo "Failed to protect 'dev' branch"

    # Cleanup
    cd "$ORIGINAL_DIR"
    rm -rf temp-repo

    echo "Completed processing $repo."
    echo "---------------------------------"
done

echo "All repositories processed successfully!"
