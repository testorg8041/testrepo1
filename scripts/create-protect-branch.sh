#!/bin/bash

# Ensure required arguments are provided
if [ "$#" -lt 2 ]; then
    echo "Error: Organization name and PAT token are required."
    echo "Usage: scripts/create-protect-branch.sh <org-name> <pat-token> [repo1 repo2 ...]"
    exit 1
fi

ORG_NAME="$1"
PAT_TOKEN="$2"
shift 2
REPOS=("$@")  # Store remaining arguments as repositories

# Authenticate with GitHub CLI using PAT
echo "Authenticating with GitHub CLI..."
echo "$PAT_TOKEN" | gh auth login --with-token

# Validate authentication
if ! gh auth status &>/dev/null; then
    echo "Error: Authentication failed. Check your PAT token permissions."
    exit 1
fi

# Fetch all repositories if none were provided
if [ "${#REPOS[@]}" -eq 0 ]; then
    echo "Fetching all repositories from organization: $ORG_NAME..."
    mapfile -t REPOS < <(gh repo list "$ORG_NAME" --limit 1000 --json name --jq '.[].name')
fi

# Function to check if a branch exists
branch_exists() {
    gh api repos/$ORG_NAME/$1/git/ref/heads/$2 >/dev/null 2>&1
}

# Function to create a branch if it doesn't exist
create_branch_if_missing() {
    local REPO=$1
    local BRANCH=$2
    local DEFAULT_BRANCH

    DEFAULT_BRANCH=$(gh api repos/$ORG_NAME/$REPO --jq '.default_branch')

    if ! branch_exists "$REPO" "$BRANCH"; then
        echo "Creating '$BRANCH' branch in $REPO..."
        gh api repos/$ORG_NAME/$REPO/git/refs --method POST --field ref=refs/heads/$BRANCH --field sha="$(gh api repos/$ORG_NAME/$REPO/git/refs/heads/$DEFAULT_BRANCH --jq '.object.sha')"
        echo "'$BRANCH' branch created successfully in $REPO."
    else
        echo "'$BRANCH' branch already exists in $REPO."
    fi
}

# Function to apply branch protection rules if the branch exists
apply_branch_protection() {
    local REPO=$1
    local BRANCH=$2

    if branch_exists "$REPO" "$BRANCH"; then
        echo "Applying branch protection rule to '$BRANCH' in $REPO..."
        gh api repos/$ORG_NAME/$REPO/branches/$BRANCH/protection --method PUT --input - <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": []
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 2
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": true,
  "required_conversation_resolution": true,
  "lock_branch": false
}
EOF
        echo "Branch protection applied to '$BRANCH' in $REPO."
    else
        echo "Skipping branch protection for '$BRANCH' in $REPO (branch does not exist)."
    fi
}

# Process each repository
for REPO in "${REPOS[@]}"; do
    echo "Processing repository: $REPO"

    # Ensure main, dev, and master branches exist
    create_branch_if_missing "$REPO" "main"
    create_branch_if_missing "$REPO" "dev"
    create_branch_if_missing "$REPO" "master"

    # Apply branch protection rules only if the branch exists
    apply_branch_protection "$REPO" "main"
    apply_branch_protection "$REPO" "dev"
    apply_branch_protection "$REPO" "master"

    echo "Completed processing $REPO."
    echo "---------------------------------"
done

echo "All repositories processed successfully!"
