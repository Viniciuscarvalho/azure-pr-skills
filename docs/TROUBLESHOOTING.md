# Troubleshooting Guide

This guide helps you solve common issues with the Azure DevOps PR Skill.

## Quick Diagnostics

Run these commands to check your setup:

```bash
# Check environment variables
echo "ORG: ${AZURE_DEVOPS_ORG:-NOT SET}"
echo "PROJECT: ${AZURE_DEVOPS_PROJECT:-NOT SET}"
echo "PAT: ${AZURE_DEVOPS_PAT:+SET (hidden)}"

# Check dependencies
bash --version
curl --version
git --version
jq --version

# Test API access
curl -s -u ":${AZURE_DEVOPS_PAT}" \
  "https://dev.azure.com/${AZURE_DEVOPS_ORG}/_apis/projects/${AZURE_DEVOPS_PROJECT}?api-version=7.1" | jq .name
```

---

## Common Errors

### Error: "AZURE_DEVOPS_ORG is required but not set"

**Exit Code:** 1

**Cause:** The `AZURE_DEVOPS_ORG` environment variable is not set.

**Solution:**

1. Add to your shell config (`~/.bashrc` or `~/.zshrc`):
```bash
export AZURE_DEVOPS_ORG="your-organization"
```

2. Reload your shell:
```bash
source ~/.bashrc  # or source ~/.zshrc
```

3. Verify:
```bash
echo $AZURE_DEVOPS_ORG
```

---

### Error: "AZURE_DEVOPS_PROJECT is required but not set"

**Exit Code:** 1

**Cause:** The `AZURE_DEVOPS_PROJECT` environment variable is not set.

**Solution:**

1. Add to your shell config:
```bash
export AZURE_DEVOPS_PROJECT="your-project"
```

2. The project name should match exactly what appears in Azure DevOps URL:
   - URL: `https://dev.azure.com/myorg/MyProject/...`
   - Variable: `export AZURE_DEVOPS_PROJECT="MyProject"`

---

### Error: "AZURE_DEVOPS_PAT is required but not set"

**Exit Code:** 1

**Cause:** The Personal Access Token is not configured.

**Solution:**

1. Create a PAT: See [PAT Setup Guide](PAT_SETUP.md)
2. Add to shell config:
```bash
export AZURE_DEVOPS_PAT="your-pat-token"
```

---

### Error: "AZURE_DEVOPS_PAT appears invalid (too short)"

**Exit Code:** 1

**Cause:** The PAT token is incomplete or corrupted.

**Solution:**

1. Azure DevOps PATs are typically 52 characters long
2. Create a new PAT at: `https://dev.azure.com/{org}/_usersSettings/tokens`
3. Copy the entire token carefully
4. Update your environment variable

---

### Error: "Authentication failed" / HTTP 401

**Exit Code:** 3

**Causes:**
- PAT has expired
- PAT doesn't have required scopes
- PAT is for wrong organization
- PAT was revoked

**Solution:**

1. Check PAT expiration at token settings
2. Create a new PAT with these scopes:
   - `vso.work` (Read Work Items)
   - `vso.work_write` (Link Work Items)
   - `vso.code_write` (Create PRs)
3. Update `AZURE_DEVOPS_PAT` environment variable

**Verify PAT works:**
```bash
curl -s -u ":${AZURE_DEVOPS_PAT}" \
  "https://dev.azure.com/${AZURE_DEVOPS_ORG}/_apis/projects?api-version=7.1" | jq '.value[].name'
```

---

### Error: "Permission denied" / HTTP 403

**Exit Code:** 3

**Causes:**
- PAT lacks required scopes
- User doesn't have permission in Azure DevOps

**Solution:**

1. Verify PAT scopes include:
   - `vso.work`
   - `vso.work_write`
   - `vso.code_write`

2. Verify user permissions in Azure DevOps:
   - Must be contributor to repository
   - Must be able to create PRs

---

### Error: "Resource not found" / HTTP 404

**Exit Code:** 3

**Causes:**
- Organization name is incorrect
- Project name is incorrect
- Repository doesn't exist

**Solution:**

1. Verify `AZURE_DEVOPS_ORG` matches your URL:
   - URL: `https://dev.azure.com/myorg/...`
   - Variable: `export AZURE_DEVOPS_ORG="myorg"`

2. Verify `AZURE_DEVOPS_PROJECT` matches your project:
   - Check spelling and capitalization
   - Project names are case-sensitive

---

### Error: "No Work Items found assigned to you"

**Exit Code:** 3

**Causes:**
- No Work Items assigned to your account
- Work Items are in closed/resolved state
- Wrong project configured

**Solution:**

1. Check Azure Boards to verify you have assigned Work Items
2. Work Items must be in Active, New, or In Progress state
3. Verify `AZURE_DEVOPS_PROJECT` is correct

---

### Error: "Not a git repository"

**Exit Code:** 2

**Cause:** Command is being run outside a git repository.

**Solution:**

Navigate to your git repository:
```bash
cd /path/to/your/repo
```

Or initialize a new repo:
```bash
git init
```

---

### Error: "No git remote 'origin' found"

**Exit Code:** 2

**Cause:** Repository doesn't have a remote named 'origin'.

**Solution:**

Add the remote:
```bash
git remote add origin https://dev.azure.com/{org}/{project}/_git/{repo}
```

Or check existing remotes:
```bash
git remote -v
```

---

### Error: "Current branch has no commits ahead of main"

**Exit Code:** 2

**Causes:**
- No commits on your branch
- Branch is synced with main

**Solution:**

1. Make at least one commit:
```bash
git add .
git commit -m "Your changes"
```

2. Or create a new branch with your changes

---

### Error: "Cannot create a Pull Request from the base branch"

**Exit Code:** 2

**Cause:** You're on the main/master branch.

**Solution:**

Create a feature branch:
```bash
git checkout -b feature/my-feature
```

Or when prompted by the skill, type `new` to create a branch.

---

### Error: "API rate limiting" / HTTP 429

**Behavior:** Skill retries automatically with exponential backoff.

**If persists:**

1. Wait a few minutes and try again
2. Reduce API calls (avoid rapid repeated invocations)
3. Check if your organization has rate limit policies

---

### Error: "Failed to push branch to origin"

**Exit Code:** 2

**Causes:**
- No push permissions to repository
- Remote branch is protected
- Network issues

**Solution:**

1. Verify you have push permissions
2. Try pushing manually:
```bash
git push -u origin HEAD
```
3. Check for branch protection rules

---

### Error: "API version issue" / "Invalid API version"

**Exit Code:** 3

**Causes:**
- Using API version 7.2 without `-preview` suffix
- Unsupported API version
- API version format incorrect

**Solution:**

The Azure DevOps API version 7.2+ requires the `-preview` suffix. This skill defaults to version 7.1 (stable).

**Option 1: Use default stable version (Recommended)**

The skill now defaults to API version 7.1 which is stable and doesn't require any suffix.

**Option 2: Use preview version**

If you need features from version 7.2+, set the environment variable with the `-preview` suffix:

```bash
export AZURE_API_VERSION="7.2-preview"
```

**Note:** Preview API versions may change and are not recommended for production use.

**Verify API version:**
```bash
echo "API Version: ${AZURE_API_VERSION:-7.1 (default)}"
```

---

## Debug Mode

Enable debug logging for detailed information:

```bash
export AZURE_DEVOPS_DEBUG="true"
/azure-pr
```

This shows:
- API requests and responses
- Internal function calls
- Variable values

Remember to disable after debugging:
```bash
unset AZURE_DEVOPS_DEBUG
```

---

## Getting Help

If you can't resolve your issue:

1. **Check logs:** Enable debug mode
2. **Verify setup:** Run diagnostics at top of this guide
3. **Search issues:** Check if others had same problem
4. **Report bug:** Open an issue with:
   - Error message
   - Debug output (with PAT redacted)
   - OS and shell version
   - Steps to reproduce

---

## Quick Reference

| Error | Exit Code | Common Fix |
|-------|-----------|------------|
| Missing env var | 1 | Set `AZURE_DEVOPS_*` variables |
| Not in git repo | 2 | Run from git repository |
| No remote origin | 2 | Add origin remote |
| No commits ahead | 2 | Make commits or new branch |
| Auth failed (401) | 3 | Check/renew PAT |
| Permission denied (403) | 3 | Check PAT scopes |
| Not found (404) | 3 | Check org/project names |
| No Work Items | 3 | Verify assigned WIs in Boards |
| User cancelled | 4 | N/A (user action) |
