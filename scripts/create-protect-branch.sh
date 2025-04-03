#!/bin/bash

# Ensure required arguments are provided
if [ "$#" -lt 2 ]; then
    echo "Error: Organization name and PAT token are required."
    echo "Usage: scripts/create-protect-branch.sh <org-name> <pat-token> [repo1 repo2 ...]"
    exit 1
fi

ORG_NAME="$1"
PAT_TOKEN="$2"

# Authenticate with GitHub CLI using PAT
echo "$PAT_TOKEN" | gh auth login --with-token

# Fetch repositories
echo "Fetching repositories from organization: $ORG_NAME..."
REPOS=$(gh repo list "$ORG_NAME" --limit 100 --json name --jq '.[].name')

if [ -z "$REPOS" ]; then
    echo "No repositories found in organization: $ORG_NAME."
    exit 1
fi

# Process each repository
for REPO in $REPOS; do
    echo "Processing repository: $REPO"
    
    # Get the default branch
    DEFAULT_BRANCH=$(gh api repos/$ORG_NAME/$REPO --jq '.default_branch')

    # Ensure 'main' branch exists
    if ! gh api repos/$ORG_NAME/$REPO/git/refs/heads/main >/dev/null 2>&1; then
        echo "Creating 'main' branch in $REPO..."
        gh api repos/$ORG_NAME/$REPO/git/refs --method POST --field ref=refs/heads/main --field sha="$(gh api repos/$ORG_NAME/$REPO/git/refs/heads/$DEFAULT_BRANCH --jq '.object.sha')"
    else
        echo "'main' branch already exists in $REPO."
    fi

    # Ensure 'dev' branch exists
    if ! gh api repos/$ORG_NAME/$REPO/git/refs/heads/dev >/dev/null 2>&1; then
        echo "Creating 'dev' branch in $REPO..."
        gh api repos/$ORG_NAME/$REPO/git/refs --method POST --field ref=refs/heads/dev --field sha="$(gh api repos/$ORG_NAME/$REPO/git/refs/heads/main --jq '.object.sha')"
    else
        echo "'dev' branch already exists in $REPO."
    fi

    echo "Completed processing $REPO."
    echo "---------------------------------"
done

echo "All repositories processed successfully!"
#!/bin/bash

# Ensure required arguments are provided
if [ "$#" -lt 2 ]; then
    echo "Error: Organization name and PAT token are required."
    echo "Usage: scripts/create-protect-branch.sh <org-name> <pat-token> [repo1 repo2 ...]"
    exit 1
fi

ORG_NAME="$1"
PAT_TOKEN="$2"

# Authenticate with GitHub CLI using PAT
echo "$PAT_TOKEN" | gh auth login --with-token

# Fetch repositories
echo "Fetching repositories from organization: $ORG_NAME..."
REPOS=$(gh repo list "$ORG_NAME" --limit 100 --json name --jq '.[].name')

if [ -z "$REPOS" ]; then
    echo "No repositories found in organization: $ORG_NAME."
    exit 1
fi

# Function to check if a branch exists
branch_exists() {
    gh api repos/$ORG_NAME/$1/git/refs/heads/$2 >/dev/null 2>&1
}

# Function to create a branch from the default branch if it doesn't exist
create_branch_if_missing() {
    local REPO=$1
    local BRANCH=$2
    local DEFAULT_BRANCH=$(gh api repos/$ORG_NAME/$REPO --jq '.default_branch')

    if ! branch_exists "$REPO" "$BRANCH"; then
        echo "Creating '$BRANCH' branch in $REPO..."
        gh api repos/$ORG_NAME/$REPO/git/refs --method POST --field ref=refs/heads/$BRANCH --field sha="$(gh api repos/$ORG_NAME/$REPO/git/refs/heads/$DEFAULT_BRANCH --jq '.object.sha')"
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
    "require_code_owner_reviews": true
  },
  "restrictions": null
}
EOF
        echo "Branch protection applied to '$BRANCH' in $REPO."
    else
        echo "Skipping branch protection for '$BRANCH' in $REPO (branch does not exist)."
    fi
}

# Process each repository
for REPO in $REPOS; do
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
