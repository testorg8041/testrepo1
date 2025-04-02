#!/bin/bash

ORG_NAME="$1"
shift
REPO_NAMES=("$@") # Remaining arguments are treated as repo names

# Ensure GitHub CLI is authenticated
if ! gh auth status &>/dev/null; then
    echo "Error: GitHub CLI is not authenticated. Run 'gh auth login' and try again."
    exit 1
fi

# If no repo names are provided, fetch all repos and ask for confirmation
if [ ${#REPO_NAMES[@]} -eq 0 ]; then
    echo "Fetching repositories from organization: $ORG_NAME..."
    REPO_NAMES=($(gh repo list "$ORG_NAME" --limit 100 --json name --jq '.[].name'))

    echo "Found ${#REPO_NAMES[@]} repositories."
    read -p "Do you want to process all repositories? (yes/no): " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        echo "Operation aborted."
        exit 0
    fi
fi

for repo in "${REPO_NAMES[@]}"; do
    echo "Processing repository: $repo"

    # Check and create 'main' branch if not exists
    if ! gh api repos/$ORG_NAME/$repo/branches/main &>/dev/null; then
        echo "Creating 'main' branch in $repo..."
        gh repo clone $ORG_NAME/$repo temp-repo -- --quiet
        cd temp-repo
        git checkout --orphan main
        git commit --allow-empty -m "Initialize main branch"
        git push origin main
        cd ..
        rm -rf temp-repo
    else
        echo "'main' branch already exists in $repo."
    fi

    # Check and create 'dev' branch if not exists
    if ! gh api repos/$ORG_NAME/$repo/branches/dev &>/dev/null; then
        echo "Creating 'dev' branch in $repo..."
        gh repo clone $ORG_NAME/$repo temp-repo -- --quiet
        cd temp-repo
        git checkout main
        git checkout -b dev
        git push origin dev
        cd ..
        rm -rf temp-repo
    else
        echo "'dev' branch already exists in $repo."
    fi

    # Set 'dev' as default branch
    echo "Setting 'dev' as the default branch for $repo..."
    gh api -X PATCH repos/$ORG_NAME/$repo -f default_branch="dev"

    # Protect 'main' branch
    echo "Protecting 'main' branch in $repo..."
    gh api -X PUT repos/$ORG_NAME/$repo/branches/main/protection -f required_status_checks='null' \
        -f enforce_admins=true -f required_pull_request_reviews='{"required_approving_review_count":1}' \
        -f restrictions='null'

    # Protect 'dev' branch
    echo "Protecting 'dev' branch in $repo..."
    gh api -X PUT repos/$ORG_NAME/$repo/branches/dev/protection -f required_status_checks='null' \
        -f enforce_admins=true -f required_pull_request_reviews='{"required_approving_review_count":1}' \
        -f restrictions='null'

    echo "Completed processing $repo."
    echo "---------------------------------"
done

echo "All repositories processed successfully!"
