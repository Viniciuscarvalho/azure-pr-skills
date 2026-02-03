# Personal Access Token (PAT) Setup Guide

This guide walks you through creating a Personal Access Token (PAT) for Azure DevOps to use with the Azure PR Skill.

## What is a PAT?

A Personal Access Token (PAT) is like a password that grants specific permissions to applications. The Azure PR Skill needs a PAT to:
- Read your Work Items
- Create Pull Requests
- Link PRs to Work Items
- Add reviewers

## Step-by-Step Guide

### Step 1: Open Azure DevOps Token Settings

1. Go to Azure DevOps: `https://dev.azure.com/{your-organization}`
2. Click on your profile icon (top-right corner)
3. Select **"Personal access tokens"**

Or go directly to:
```
https://dev.azure.com/{your-organization}/_usersSettings/tokens
```

### Step 2: Create New Token

1. Click **"+ New Token"** button
2. Fill in the form:

| Field | Value |
|-------|-------|
| **Name** | `Claude PR Skill` (or any descriptive name) |
| **Organization** | Select your organization |
| **Expiration** | Choose expiration (recommended: 90 days) |
| **Scopes** | See below |

### Step 3: Select Scopes

You need **Custom defined** scopes with the following permissions:

| Scope | Permission | Why Needed |
|-------|------------|------------|
| **Work Items** | `vso.work` (Read) | Fetch your assigned Work Items |
| **Work Items** | `vso.work_write` (Read & Write) | Link PR to Work Item |
| **Code** | `vso.code_write` (Read & Write) | Create Pull Requests |

#### How to Select:

1. Click **"Show all scopes"** at the bottom
2. Find and check these scopes:
   - ✅ Work Items: **Read** (`vso.work`)
   - ✅ Work Items: **Read & Write** (`vso.work_write`)
   - ✅ Code: **Read & Write** (`vso.code_write`)

### Step 4: Create and Copy Token

1. Click **"Create"** button
2. **IMPORTANT**: Copy the token immediately!
3. The token will only be shown once

⚠️ **Warning**: If you lose the token, you'll need to create a new one.

### Step 5: Set Environment Variable

Add to your shell configuration file (`~/.bashrc` for Bash or `~/.zshrc` for Zsh):

```bash
# Azure DevOps PR Skill Configuration
export AZURE_DEVOPS_ORG="your-organization"
export AZURE_DEVOPS_PROJECT="your-project"
export AZURE_DEVOPS_PAT="your-token-here"
```

Replace:
- `your-organization` - Your Azure DevOps organization name
- `your-project` - Your project name
- `your-token-here` - The token you just copied

### Step 6: Reload Shell

```bash
# For Bash
source ~/.bashrc

# For Zsh
source ~/.zshrc
```

### Step 7: Verify Configuration

Run the skill to test:

```bash
/azure-pr
```

If configuration is correct, you should see:
```
✓ Environment validated
✓ Git repository validated
📥 Fetching Work Items...
```

## Security Best Practices

### ✅ Do:

- Set an expiration date (90 days recommended)
- Use minimum required scopes
- Store PAT only in environment variables
- Rotate tokens regularly

### ❌ Don't:

- Share your PAT with others
- Commit PAT to source control
- Store PAT in plain text files
- Give Full Access scope (use specific scopes)

## Managing Tokens

### View All Tokens

Go to: `https://dev.azure.com/{org}/_usersSettings/tokens`

### Revoke a Token

1. Go to token settings
2. Find the token
3. Click **"Revoke"**

### Regenerate Token

Tokens cannot be regenerated. If expired or lost:
1. Create a new token
2. Update your environment variable
3. Optionally revoke the old token

## Troubleshooting

### "Authentication failed"

**Possible causes:**
1. PAT has expired
2. PAT doesn't have required scopes
3. PAT is for wrong organization
4. PAT was revoked

**Solution:**
1. Go to token settings
2. Check if token is active
3. Create a new token if needed
4. Update `AZURE_DEVOPS_PAT` environment variable

### "PAT appears invalid (too short)"

**Cause:** The PAT wasn't copied completely.

**Solution:**
1. Create a new PAT
2. Copy the entire token (typically 52 characters)
3. Update environment variable

### "Access denied" or "403 Forbidden"

**Cause:** PAT doesn't have required scopes.

**Solution:**
1. Create a new PAT with correct scopes:
   - `vso.work`
   - `vso.work_write`
   - `vso.code_write`

## Reference

- [Azure DevOps PAT Documentation](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate)
- [PAT Scopes Reference](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/oauth?view=azure-devops#scopes)

---

Need help? Check the [Troubleshooting Guide](TROUBLESHOOTING.md).
