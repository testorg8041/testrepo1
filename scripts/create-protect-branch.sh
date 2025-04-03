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

    # Ensure 'production' branch exists
    if ! gh api repos/$ORG_NAME/$REPO/git/refs/heads/production >/dev/null 2>&1; then
        echo "Creating 'production' branch in $REPO..."
        gh api repos/$ORG_NAME/$REPO/git/refs --method POST --field ref=refs/heads/production --field sha="$(gh api repos/$ORG_NAME/$REPO/git/refs/heads/main --jq '.object.sha')"
    else
        echo "'production' branch already exists in $REPO."
    fi

    echo "Completed processing $REPO."
    echo "---------------------------------"
done

echo "All repositories processed successfully!"
