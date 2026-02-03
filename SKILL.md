---
name: azure-pr
description: Automate Azure DevOps Pull Request creation with Work Item linking
invocation: /azure-pr
---

# Azure DevOps PR Automation

Automates the creation of Pull Requests in Azure DevOps with automatic Work Item linkage. This skill streamlines the PR creation process by fetching your active Work Items, letting you select one, and creating a well-formatted PR with all relevant information.

## Execution

When user invokes `/azure-pr`, execute:

```bash
#!/usr/bin/env bash
exec ~/.claude/skills/azure-devops-pr/azure-pr.sh "$@"
```

## Prerequisites

Before using this skill, ensure the following environment variables are set:

### Required Variables

| Variable | Description |
|----------|-------------|
| `AZURE_DEVOPS_ORG` | Your Azure DevOps organization name |
| `AZURE_DEVOPS_PROJECT` | Project name where PRs will be created |
| `AZURE_DEVOPS_PAT` | Personal Access Token with required scopes |

### Optional Variables

| Variable | Description |
|----------|-------------|
| `AZURE_DEVOPS_REVIEWERS` | Comma-separated list of reviewer GUIDs |
| `AZURE_DEVOPS_TARGET_BRANCH` | Override default base branch (main/master) |
| `AZURE_DEVOPS_DEBUG` | Set to "true" to enable debug logging |

### Setting Up PAT

1. Go to: `https://dev.azure.com/{your-org}/_usersSettings/tokens`
2. Create new token with scopes:
   - `vso.work` (Read Work Items)
   - `vso.work_write` (Link Work Items)
   - `vso.code_write` (Create Pull Requests)
3. Set in your shell config (~/.bashrc or ~/.zshrc):

```bash
export AZURE_DEVOPS_ORG="your-organization"
export AZURE_DEVOPS_PROJECT="your-project"
export AZURE_DEVOPS_PAT="your-personal-access-token"
```

4. Reload your shell:

```bash
source ~/.bashrc  # or source ~/.zshrc
```

## System Prompt

You are helping the developer create a Pull Request in Azure DevOps with automatic Work Item linkage.

**Your role:**
1. Guide them through selecting a Work Item from their active assignments
2. Help them decide whether to create a new branch or use their current one
3. Explain what's happening at each step (fetching Work Items, creating PR, linking)
4. Show clear progress indicators and celebrate success with them

**Be conversational and helpful:**
- If they encounter errors, help them understand what went wrong
- Provide actionable suggestions for fixing configuration issues
- Explain what the PR will contain (title, description, acceptance criteria)

**Remember:**
- The skill automates the tedious parts, not the coding
- The PR is created as a draft so they can review before marking ready
- All data comes from their Work Item - no need to retype anything

## Usage Examples

### Basic Usage

```
Developer: /azure-pr

Claude: I'll help you create a Pull Request! Let me run the skill...

[Skill starts and displays progress]

🚀 Azure DevOps PR Automation
──────────────────────────────────────────────────

[1/6] Validating environment...
✓ Environment validated

[2/6] Validating git repository...
✓ Git repository validated

[3/6] Fetching Work Items...
✓ Work Items fetched

📋 Your Active Work Items:

  [1] #12345 [Bug] - Fix login validation error (Active)
  [2] #12346 [Feature] - Add dark mode support (New)
  [3] #12347 [Task] - Update documentation (In Progress)

Select Work Item (1-3): 1

📌 Selected Work Item:
   ID:    #12345
   Type:  Bug
   Title: Fix login validation error
   State: Active

[4/6] Branch selection...

🔀 Branch Options:
   new     - Create a new feature branch from this Work Item
   current - Use the current branch (must have commits ahead)

Create new branch or use current? [new/current]: current

✓ Branch: feature/fix-login

[5/6] Creating Pull Request...
✓ Branch pushed
✓ Pull Request created (Draft)

[6/6] Finalizing...
✓ Linked to Work Item #12345
✓ Reviewers added

🎉 PR created successfully:
   https://dev.azure.com/my-org/my-project/_git/my-repo/pullrequest/789
```

### Creating a New Branch

```
Developer: /azure-pr

[After selecting Work Item]

Create new branch or use current? [new/current]: new

Suggested branch name: feature/WI-12345-fix-login-validation-error
Enter to confirm or type a new name: [ENTER]

✓ Branch 'feature/WI-12345-fix-login-validation-error' created
```

## Troubleshooting

### Error: "AZURE_DEVOPS_ORG is required but not set"

**Solution:** Set your organization name:
```bash
export AZURE_DEVOPS_ORG="your-organization"
```

Add this to `~/.bashrc` or `~/.zshrc` for persistence.

---

### Error: "AZURE_DEVOPS_PAT appears invalid (too short)"

**Causes:**
- PAT was not copied correctly
- PAT is truncated

**Solution:** 
1. Go to https://dev.azure.com/{org}/_usersSettings/tokens
2. Create a new PAT or view the existing one
3. Copy the entire token (typically 52 characters)
4. Set it in your shell:
```bash
export AZURE_DEVOPS_PAT="your-complete-token-here"
```

---

### Error: "Authentication failed"

**Causes:**
- PAT has expired
- PAT doesn't have required scopes
- PAT is for wrong organization

**Solution:**
1. Create a new PAT at: `https://dev.azure.com/{org}/_usersSettings/tokens`
2. Ensure these scopes are selected:
   - `vso.work` (Read Work Items)
   - `vso.work_write` (Link Work Items)
   - `vso.code_write` (Create Pull Requests)
3. Set the new PAT in your environment

---

### Error: "No Work Items found assigned to you"

**Causes:**
- No Work Items assigned to you in Azure Boards
- Wrong project configured
- Work Items are in closed/resolved states

**Solution:**
1. Verify you have active Work Items in Azure Boards
2. Check `AZURE_DEVOPS_PROJECT` matches your project name exactly
3. Ensure Work Items are in Active, New, or In Progress states

---

### Error: "Not a git repository"

**Cause:** You're running the command outside of a git repository.

**Solution:** Navigate to your git repository:
```bash
cd /path/to/your/repo
```

---

### Error: "No git remote 'origin' found"

**Cause:** Repository doesn't have a remote configured.

**Solution:**
```bash
git remote add origin https://dev.azure.com/{org}/{project}/_git/{repo}
```

---

### Error: "Current branch has no commits ahead of main"

**Causes:**
- No commits on your branch yet
- Branch is synced with main/master

**Solution:**
1. Make at least one commit before creating a PR
2. Or choose `new` to create a fresh feature branch

---

### Error: "Cannot create a Pull Request from the base branch"

**Cause:** You're on main/master branch.

**Solution:**
1. Create a feature branch first:
```bash
git checkout -b feature/my-feature
```
2. Or choose `new` when prompted to create a branch from the Work Item

---

## What This Skill Does

| Step | Action |
|------|--------|
| 1 | ✅ Validates your Azure DevOps configuration |
| 2 | ✅ Validates you're in a git repository with origin remote |
| 3 | ✅ Fetches your active Work Items (Active, New, In Progress) |
| 4 | ✅ Lets you select which Work Item this PR is for |
| 5 | ✅ Creates new branch or validates your current one |
| 6 | ✅ Builds a PR with title, description, and acceptance criteria |
| 7 | ✅ Creates PR in Draft state |
| 8 | ✅ Links PR to selected Work Item |
| 9 | ✅ Adds configured reviewers automatically |
| 10 | ✅ Displays clickable PR URL |

## What This Skill Doesn't Do

- ❌ Modify your code or make commits
- ❌ Run builds or tests
- ❌ Approve or merge PRs
- ❌ Create or update Work Items
- ❌ Handle merge conflicts
- ❌ Push changes (it will push your branch before creating PR)

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success - PR created |
| 1 | Configuration error (missing env vars) |
| 2 | Git repository error |
| 3 | Azure DevOps API error |
| 4 | User cancelled operation |

---

*This skill saves you ~5 minutes per PR by automating the tedious parts of PR creation!*
