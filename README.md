# Branch Management Automation

This repository contains automation scripts to standardize branch structure and protection rules across repositories in a GitHub organization.

## Features

- Creates `main` and `dev` branches in all repositories if they don't exist
- Sets `dev` as the default branch
- Applies branch protection rules to both `main` and `dev` branches
  - Requires pull request reviews (at least 1 approval)
  - Enforces admin restrictions
  - Prevents force pushes

## Setup Instructions

### 1. Create a Personal Access Token (PAT)

The workflow requires a Personal Access Token with the following scopes:
- `repo` (Full control of private repositories)
- `admin:org` (Full control of orgs and teams, read and write org projects)

To create a PAT:
1. Go to [GitHub Personal Access Tokens](https://github.com/settings/tokens)
2. Click "Generate new token"
3. Select the scopes mentioned above
4. Copy the generated token

### 2. Add the PAT as a Repository Secret

1. Go to your repository settings
2. Navigate to "Secrets and variables" > "Actions"
3. Click "New repository secret"
4. Name: `PAT`
5. Value: Paste your Personal Access Token
6. Click "Add secret"

## Usage

### Using the GitHub Actions Workflow

1. Go to the "Actions" tab in your repository
2. Select the "Update Branches" workflow
3. Click "Run workflow"
4. Enter the organization name (e.g., `testorg8041`)
5. Click "Run workflow"

The workflow will:
- Fetch all repositories in the specified organization
- Create and protect branches as needed
- Output progress in the workflow logs

### Using the Script Locally

You can also run the script locally:

```bash
# Authenticate with GitHub CLI first
gh auth login

# Run for all repositories in an organization
./scripts/create-protect-branch.sh your-org-name

# Run for specific repositories
./scripts/create-protect-branch.sh your-org-name repo1 repo2 repo3
```

## Troubleshooting

- **Authentication Issues**: Ensure your PAT has the correct scopes and hasn't expired
- **Permission Errors**: Verify you have admin access to the organization and repositories
- **API Rate Limits**: For large organizations, you might hit GitHub API rate limits. Consider running the script for specific repositories instead of all at once.