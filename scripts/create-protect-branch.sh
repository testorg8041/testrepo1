#!/bin/bash

# Get organization name and GitHub token
ORG_NAME="$1"
GITHUB_TOKEN="$2"
shift 2
REPO_NAMES=("$@") # Remaining arguments are treated as repo names

# If GITHUB_TOKEN is not provided, try to get it from environment
if [ -z "$GITHUB_TOKEN" ] && [ -n "$GITHUB_ACTIONS" ]; then
    GITHUB_TOKEN="${GITHUB_TOKEN:-$PAT}"
fi

# Validate required parameters
if [ -z "$ORG_NAME" ]; then
    echo "Error: Organization name is required."
    echo "Usage: $0 <org-name> [github-token] [repo1 repo2 ...]"
    exit 1
fi

# Ensure GitHub CLI is authenticated
if ! gh auth status &>/dev/null; then
    echo "Error: GitHub CLI is not authenticated. Run 'gh auth login' and try again."
    exit 1
fi

# If no repo names are provided, fetch all repos and ask for confirmation
if [ ${#REPO_NAMES[@]} -eq 0 ]; then
    echo "Fetching repositories from organization: $ORG_NAME..."
    
    # Add error handling for repository listing
    if ! REPO_NAMES=($(gh repo list "$ORG_NAME" --limit 100 --json name --jq '.[].name' 2>/dev/null)); then
        echo "Error: Failed to fetch repositories from organization $ORG_NAME."
        echo "Please check if the organization exists and you have proper access."
        exit 1
    fi
    
    # Check if any repositories were found
    if [ ${#REPO_NAMES[@]} -eq 0 ]; then
        echo "No repositories found in organization $ORG_NAME."
        exit 0
    fi

    echo "Found ${#REPO_NAMES[@]} repositories."
    # Check if running in GitHub Actions or other CI environment
    if [ -n "$GITHUB_ACTIONS" ] || [ -n "$CI" ]; then
        echo "Running in CI environment - automatically proceeding with all repositories."
    else
        # Only prompt for confirmation in interactive environments
        read -p "Do you want to process all repositories? (yes/no): " CONFIRM
        if [[ "$CONFIRM" != "yes" ]]; then
            echo "Operation aborted."
            exit 0
        fi
        
        # If not in CI and no token provided, check if gh is authenticated
        if [ -z "$GITHUB_TOKEN" ]; then
            if ! gh auth status &>/dev/null; then
                echo "Error: GitHub CLI is not authenticated and no token provided."
                echo "Run 'gh auth login' or provide a token as the second parameter."
                exit 1
            fi
        fi
    fi
fi

# Function to handle errors
handle_error() {
    echo "Error: $1"
    if [ -d "temp-repo" ]; then
        cd $ORIGINAL_DIR
        rm -rf temp-repo
    fi
    return 1
}

# Store original directory
ORIGINAL_DIR=$(pwd)

for repo in "${REPO_NAMES[@]}"; do
    echo "Processing repository: $repo"
    
    # Verify repository exists
    if ! gh api repos/$ORG_NAME/$repo &>/dev/null; then
        echo "Warning: Repository $ORG_NAME/$repo does not exist or you don't have access. Skipping."
        continue
    fi

    # Check and create 'main' branch if not exists
    if ! gh api repos/$ORG_NAME/$repo/branches/main &>/dev/null; then
        echo "Creating 'main' branch in $repo..."
        if ! gh repo clone $ORG_NAME/$repo temp-repo -- --quiet; then
            handle_error "Failed to clone repository $ORG_NAME/$repo" && continue
        fi
        
        cd temp-repo || { handle_error "Failed to change directory to temp-repo" && continue; }
        
        # Configure git identity for this repository only
        git config user.email "github-actions@github.com"
        git config user.name "GitHub Actions"
        
        if ! git checkout --orphan main; then
            handle_error "Failed to create orphan branch 'main'" && continue
        fi
        
        # Create an empty commit
        if ! git commit --allow-empty -m "Initialize main branch"; then
            handle_error "Failed to create initial commit on 'main' branch" && continue
        fi
        
        # Use token-based authentication for push
        REPO_URL="https://${GITHUB_TOKEN}@github.com/${ORG_NAME}/${repo}.git"
        if ! git push "${REPO_URL}" main; then
            handle_error "Failed to push 'main' branch to remote" && continue
        fi
        
        cd $ORIGINAL_DIR || { handle_error "Failed to return to original directory" && continue; }
        rm -rf temp-repo
    else
        echo "'main' branch already exists in $repo."
    fi

    # Check and create 'dev' branch if not exists
    if ! gh api repos/$ORG_NAME/$repo/branches/dev &>/dev/null; then
        echo "Creating 'dev' branch in $repo..."
        if ! gh repo clone $ORG_NAME/$repo temp-repo -- --quiet; then
            handle_error "Failed to clone repository $ORG_NAME/$repo" && continue
        fi
        
        cd temp-repo || { handle_error "Failed to change directory to temp-repo" && continue; }
        
        # Configure git identity for this repository only
        git config user.email "github-actions@github.com"
        git config user.name "GitHub Actions"
        
        # Try to checkout main, but if it fails, create it as an orphan branch
        if ! git checkout main; then
            echo "Main branch not found locally, creating it..."
            if ! git checkout --orphan main; then
                handle_error "Failed to create orphan 'main' branch" && continue
            fi
            # Create an empty commit on main if needed
            if ! git commit --allow-empty -m "Initialize main branch"; then
                handle_error "Failed to create initial commit on 'main' branch" && continue
            fi
        fi
        
        if ! git checkout -b dev; then
            handle_error "Failed to create 'dev' branch" && continue
        fi
        
        # Use token-based authentication for push
        REPO_URL="https://${GITHUB_TOKEN}@github.com/${ORG_NAME}/${repo}.git"
        if ! git push "${REPO_URL}" dev; then
            handle_error "Failed to push 'dev' branch to remote" && continue
        fi
        
        cd $ORIGINAL_DIR || { handle_error "Failed to return to original directory" && continue; }
        rm -rf temp-repo
    else
        echo "'dev' branch already exists in $repo."
    fi

    # Set 'dev' as default branch
    echo "Setting 'dev' as the default branch for $repo..."
    if ! gh api -X PATCH repos/$ORG_NAME/$repo -f default_branch="dev" &>/dev/null; then
        echo "Warning: Failed to set 'dev' as default branch for $repo. Continuing with other operations."
    fi

    # Protect 'main' branch
    echo "Protecting 'main' branch in $repo..."
    if ! gh api -X PUT repos/$ORG_NAME/$repo/branches/main/protection \
        -f required_status_checks='null' \
        -f enforce_admins=true \
        -f required_pull_request_reviews='{"required_approving_review_count":1}' \
        -f restrictions='null' &>/dev/null; then
        echo "Warning: Failed to protect 'main' branch in $repo. Continuing with other operations."
    fi

    # Protect 'dev' branch
    echo "Protecting 'dev' branch in $repo..."
    if ! gh api -X PUT repos/$ORG_NAME/$repo/branches/dev/protection \
        -f required_status_checks='null' \
        -f enforce_admins=true \
        -f required_pull_request_reviews='{"required_approving_review_count":1}' \
        -f restrictions='null' &>/dev/null; then
        echo "Warning: Failed to protect 'dev' branch in $repo. Continuing with other operations."
    fi

    echo "Completed processing $repo."
    echo "---------------------------------"
done

echo "All repositories processed successfully!"
