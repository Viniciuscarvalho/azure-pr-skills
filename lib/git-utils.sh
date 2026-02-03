#!/usr/bin/env bash
# File: ~/.claude/skills/azure-devops-pr/lib/git-utils.sh
# Git Operations Module for Azure DevOps PR Automation Skill
# This module handles all Git-related operations: validation, branch detection,
# branch creation, and state verification.

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Maximum length for kebab-case title in branch name
: "${GIT_BRANCH_TITLE_MAX_LENGTH:=50}"

# Branch name prefix
: "${GIT_BRANCH_PREFIX:=feature}"

# Load config module for logging functions if not already loaded
if ! type -t error &>/dev/null; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  if [[ -f "${SCRIPT_DIR}/config.sh" ]]; then
    source "${SCRIPT_DIR}/config.sh"
  fi
fi

# ==============================================================================
# REPOSITORY VALIDATION
# ==============================================================================

# Validate that we're inside a Git repository with a remote origin
# Also warns (but doesn't block) about uncommitted changes
#
# Returns:
#   exit code: 0 if valid, 1 if not a git repo, 2 if no remote origin
#
# Example:
#   if validate_git_repo; then
#     echo "Git repository is valid"
#   fi
validate_git_repo() {
  debug "Validating git repository..."
  
  # Check if we're in a git repository
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    error "Not a git repository"
    echo "   → Run this command from within a git repository" >&2
    echo "   → Initialize with: git init" >&2
    return 1
  fi
  
  debug "Git directory found: $(git rev-parse --git-dir)"
  
  # Check if remote 'origin' exists
  if ! git remote get-url origin > /dev/null 2>&1; then
    error "No git remote 'origin' found"
    echo "   → Add a remote with: git remote add origin <url>" >&2
    echo "   → For Azure DevOps: git remote add origin https://dev.azure.com/{org}/{project}/_git/{repo}" >&2
    return 2
  fi
  
  local remote_url
  remote_url=$(git remote get-url origin)
  debug "Remote origin URL: ${remote_url}"
  
  # Check for uncommitted changes (warning only, non-blocking)
  if has_uncommitted_changes; then
    warn "You have uncommitted changes"
    echo "   → Consider committing or stashing before creating a PR" >&2
  fi
  
  # Check for untracked files (informational)
  local untracked_count
  untracked_count=$(git ls-files --others --exclude-standard | wc -l | tr -d ' ')
  if [[ "$untracked_count" -gt 0 ]]; then
    debug "Found ${untracked_count} untracked files"
  fi
  
  debug "Git repository validation passed"
  return 0
}

# Check if there are uncommitted changes (staged or unstaged)
#
# Returns:
#   exit code: 0 if there are changes, 1 if clean
has_uncommitted_changes() {
  # Check for staged changes
  if ! git diff --cached --quiet 2>/dev/null; then
    return 0
  fi
  
  # Check for unstaged changes
  if ! git diff --quiet 2>/dev/null; then
    return 0
  fi
  
  return 1
}

# Check if repository has any commits
#
# Returns:
#   exit code: 0 if has commits, 1 if empty
has_commits() {
  git rev-parse HEAD > /dev/null 2>&1
}

# ==============================================================================
# BRANCH DETECTION
# ==============================================================================

# Detect the default branch (main, master, or other)
# Uses git remote show to get the HEAD branch of origin
#
# Returns:
#   stdout: Default branch name (e.g., "main" or "master")
#   exit code: 0 on success, 1 if unable to detect
#
# Example:
#   default_branch=$(get_default_branch)
get_default_branch() {
  local default_branch
  
  debug "Detecting default branch..."
  
  # Method 1: Use git remote show (most reliable, but requires network)
  default_branch=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
  
  if [[ -n "$default_branch" ]]; then
    debug "Default branch detected via remote show: ${default_branch}"
    echo "$default_branch"
    return 0
  fi
  
  # Method 2: Check local refs for common branch names
  for branch in main master develop; do
    if git show-ref --verify --quiet "refs/remotes/origin/${branch}" 2>/dev/null; then
      debug "Default branch detected via refs: ${branch}"
      echo "$branch"
      return 0
    fi
  done
  
  # Method 3: Use symbolic-ref if available
  default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
  
  if [[ -n "$default_branch" ]]; then
    debug "Default branch detected via symbolic-ref: ${default_branch}"
    echo "$default_branch"
    return 0
  fi
  
  # Fallback: assume 'main' (most common default)
  warn "Could not detect default branch, assuming 'main'"
  echo "main"
  return 0
}

# Get the currently checked out branch name
#
# Returns:
#   stdout: Current branch name
#   exit code: 0 on success, 1 if in detached HEAD
get_current_branch() {
  local branch
  branch=$(git branch --show-current 2>/dev/null)
  
  if [[ -z "$branch" ]]; then
    # In detached HEAD state
    return 1
  fi
  
  echo "$branch"
}

# Check if a branch exists locally
#
# Args:
#   $1 - Branch name
#
# Returns:
#   exit code: 0 if exists, 1 if not
branch_exists_locally() {
  local branch="$1"
  git show-ref --verify --quiet "refs/heads/${branch}" 2>/dev/null
}

# Check if a branch exists on remote
#
# Args:
#   $1 - Branch name
#
# Returns:
#   exit code: 0 if exists, 1 if not
branch_exists_remote() {
  local branch="$1"
  git show-ref --verify --quiet "refs/remotes/origin/${branch}" 2>/dev/null
}

# ==============================================================================
# BRANCH CREATION
# ==============================================================================

# Convert a string to kebab-case
# - Converts to lowercase
# - Replaces non-alphanumeric characters with hyphens
# - Collapses multiple hyphens
# - Removes leading/trailing hyphens
# - Limits to specified length
#
# Args:
#   $1 - Input string
#   $2 - Max length (optional, default: GIT_BRANCH_TITLE_MAX_LENGTH)
#
# Returns:
#   stdout: Kebab-case string
#
# Example:
#   to_kebab_case "Fix Authentication Timeout in API"
#   # Returns: "fix-authentication-timeout-in-api"
to_kebab_case() {
  local input="$1"
  local max_length="${2:-$GIT_BRANCH_TITLE_MAX_LENGTH}"
  
  echo "$input" | \
    tr '[:upper:]' '[:lower:]' | \
    sed 's/[^a-z0-9]/-/g' | \
    sed 's/--*/-/g' | \
    sed 's/^-//' | \
    sed 's/-$//' | \
    cut -c1-"${max_length}"
}

# Generate a suggested branch name from Work Item info
#
# Args:
#   $1 - Work Item ID
#   $2 - Work Item Title
#   $3 - Prefix (optional, default: GIT_BRANCH_PREFIX)
#
# Returns:
#   stdout: Suggested branch name (e.g., "feature/WI-12345-fix-bug")
generate_branch_name() {
  local wi_id="$1"
  local wi_title="$2"
  local prefix="${3:-$GIT_BRANCH_PREFIX}"
  
  local title_kebab
  title_kebab=$(to_kebab_case "$wi_title")
  
  echo "${prefix}/WI-${wi_id}-${title_kebab}"
}

# Create a new feature branch from Work Item info
# Prompts user to confirm or edit the suggested branch name
#
# Args:
#   $1 - Work Item ID
#   $2 - Work Item Title
#
# Returns:
#   stdout: Final branch name
#   exit code: 0 on success, 1 on failure
#
# Example:
#   branch=$(create_feature_branch "12345" "Fix authentication timeout")
create_feature_branch() {
  local wi_id="$1"
  local wi_title="$2"
  
  if [[ -z "$wi_id" || -z "$wi_title" ]]; then
    error "Work Item ID and title are required"
    return 1
  fi
  
  # Generate suggested branch name
  local suggested_name
  suggested_name=$(generate_branch_name "$wi_id" "$wi_title")
  
  debug "Suggested branch name: ${suggested_name}"
  
  # Prompt user to confirm or edit
  local branch_name
  echo "" >&2
  read -r -p "Branch name [${suggested_name}]: " branch_name
  branch_name="${branch_name:-$suggested_name}"
  
  # Validate branch name
  if ! is_valid_branch_name "$branch_name"; then
    error "Invalid branch name: ${branch_name}"
    return 1
  fi
  
  # Check if branch already exists
  if branch_exists_locally "$branch_name"; then
    error "Branch '${branch_name}' already exists locally"
    echo "   → Delete it with: git branch -D ${branch_name}" >&2
    echo "   → Or choose a different name" >&2
    return 1
  fi
  
  # Get base branch
  local base_branch
  base_branch=$(get_default_branch)
  
  # Fetch latest from origin to ensure we have the latest base
  debug "Fetching latest from origin..."
  git fetch origin "$base_branch" --quiet 2>/dev/null || true
  
  # Create and checkout branch
  info "Creating branch '${branch_name}' from 'origin/${base_branch}'..."
  
  if ! git checkout -b "$branch_name" "origin/${base_branch}" 2>/dev/null; then
    error "Failed to create branch"
    echo "   → Ensure 'origin/${base_branch}' exists" >&2
    echo "   → Run: git fetch origin" >&2
    return 1
  fi
  
  success "Branch '${branch_name}' created and checked out"
  echo "$branch_name"
}

# Create a feature branch non-interactively (for scripting)
# Does not prompt for input, uses suggested name directly
#
# Args:
#   $1 - Work Item ID
#   $2 - Work Item Title
#   $3 - Custom branch name (optional, uses generated name if not provided)
#
# Returns:
#   stdout: Final branch name
#   exit code: 0 on success, 1 on failure
create_feature_branch_noninteractive() {
  local wi_id="$1"
  local wi_title="$2"
  local custom_name="${3:-}"
  
  local branch_name
  if [[ -n "$custom_name" ]]; then
    branch_name="$custom_name"
  else
    branch_name=$(generate_branch_name "$wi_id" "$wi_title")
  fi
  
  # Check if branch already exists
  if branch_exists_locally "$branch_name"; then
    error "Branch '${branch_name}' already exists"
    return 1
  fi
  
  local base_branch
  base_branch=$(get_default_branch)
  
  git fetch origin "$base_branch" --quiet 2>/dev/null || true
  
  # Suppress all git output, only return branch name on success
  if ! git checkout -b "$branch_name" "origin/${base_branch}" > /dev/null 2>&1; then
    return 1
  fi
  
  echo "$branch_name"
}

# Validate that a branch name is valid for Git
#
# Args:
#   $1 - Branch name
#
# Returns:
#   exit code: 0 if valid, 1 if invalid
is_valid_branch_name() {
  local name="$1"
  
  # Cannot be empty
  if [[ -z "$name" ]]; then
    return 1
  fi
  
  # Cannot start with - or .
  if [[ "$name" =~ ^[-\.] ]]; then
    return 1
  fi
  
  # Cannot contain certain characters
  if [[ "$name" =~ [\~\^:\?\*\[\\\]] ]]; then
    return 1
  fi
  
  # Cannot contain consecutive dots
  if [[ "$name" =~ \.\. ]]; then
    return 1
  fi
  
  # Cannot end with .lock or /
  if [[ "$name" =~ (\.lock|/)$ ]]; then
    return 1
  fi
  
  # Use git check-ref-format for comprehensive validation
  git check-ref-format --branch "$name" > /dev/null 2>&1
}

# ==============================================================================
# BRANCH VALIDATION
# ==============================================================================

# Validate that the current branch is ready for PR creation
# Checks that:
# - Not in detached HEAD state
# - Branch has commits ahead of the base branch
#
# Returns:
#   stdout: Current branch name
#   exit code: 0 if valid, 1 if not
#
# Example:
#   if branch=$(validate_current_branch); then
#     echo "Branch $branch is ready for PR"
#   fi
validate_current_branch() {
  debug "Validating current branch..."
  
  # Get current branch
  local current_branch
  current_branch=$(get_current_branch)
  
  if [[ -z "$current_branch" ]]; then
    error "Not on any branch (detached HEAD state)"
    echo "   → Checkout a branch with: git checkout <branch-name>" >&2
    echo "   → Or create a new branch with: git checkout -b <branch-name>" >&2
    return 1
  fi
  
  debug "Current branch: ${current_branch}"
  
  # Get base branch
  local base_branch
  base_branch=$(get_default_branch)
  
  debug "Base branch: ${base_branch}"
  
  # Check if current branch is the same as base branch
  if [[ "$current_branch" == "$base_branch" ]]; then
    error "Cannot create PR from '${base_branch}' to itself"
    echo "   → Create a new branch for your changes" >&2
    echo "   → Run: git checkout -b feature/your-feature" >&2
    return 1
  fi
  
  # Fetch latest base branch info
  git fetch origin "$base_branch" --quiet 2>/dev/null || true
  
  # Count commits ahead of base branch
  local ahead_count
  ahead_count=$(git rev-list --count "origin/${base_branch}..HEAD" 2>/dev/null || echo "0")
  
  debug "Commits ahead of ${base_branch}: ${ahead_count}"
  
  if [[ "$ahead_count" -eq 0 ]]; then
    error "Current branch '${current_branch}' has no commits ahead of '${base_branch}'"
    echo "   → Make at least one commit before creating a PR" >&2
    echo "   → Or create a new branch from your changes" >&2
    return 1
  fi
  
  # Check if branch is behind (informational warning)
  local behind_count
  behind_count=$(git rev-list --count "HEAD..origin/${base_branch}" 2>/dev/null || echo "0")
  
  if [[ "$behind_count" -gt 0 ]]; then
    warn "Branch is ${behind_count} commits behind '${base_branch}'"
    echo "   → Consider rebasing: git rebase origin/${base_branch}" >&2
  fi
  
  debug "Branch validation passed"
  echo "$current_branch"
}

# Get the number of commits ahead of the base branch
#
# Returns:
#   stdout: Number of commits ahead
get_commits_ahead() {
  local base_branch
  base_branch=$(get_default_branch)
  
  git rev-list --count "origin/${base_branch}..HEAD" 2>/dev/null || echo "0"
}

# Get the number of commits behind the base branch
#
# Returns:
#   stdout: Number of commits behind
get_commits_behind() {
  local base_branch
  base_branch=$(get_default_branch)
  
  git rev-list --count "HEAD..origin/${base_branch}" 2>/dev/null || echo "0"
}

# ==============================================================================
# PUSH OPERATIONS
# ==============================================================================

# Push the current branch to origin
# Creates the remote tracking branch if it doesn't exist
#
# Returns:
#   exit code: 0 on success, 1 on failure
push_current_branch() {
  local current_branch
  current_branch=$(get_current_branch)
  
  if [[ -z "$current_branch" ]]; then
    error "Not on any branch"
    return 1
  fi
  
  info "Pushing '${current_branch}' to origin..."
  
  if git push -u origin "$current_branch" 2>/dev/null; then
    success "Branch pushed successfully"
    return 0
  else
    error "Failed to push branch"
    echo "   → Check your network connection" >&2
    echo "   → Verify you have push permissions" >&2
    return 1
  fi
}

# Check if the current branch has been pushed to origin
#
# Returns:
#   exit code: 0 if pushed, 1 if not
is_branch_pushed() {
  local current_branch
  current_branch=$(get_current_branch) || return 1
  
  branch_exists_remote "$current_branch"
}

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# Get the remote URL for origin
#
# Returns:
#   stdout: Remote URL
get_remote_url() {
  git remote get-url origin 2>/dev/null
}

# Extract repository name from remote URL
# Handles both HTTPS and SSH formats
#
# Returns:
#   stdout: Repository name
get_repository_name() {
  local remote_url
  remote_url=$(get_remote_url) || return 1
  
  # Extract repo name from various URL formats
  if [[ "$remote_url" =~ /_git/([^/]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]%.git}"
  elif [[ "$remote_url" =~ :v3/[^/]+/[^/]+/([^/]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]%.git}"
  elif [[ "$remote_url" =~ /([^/]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]%.git}"
  else
    return 1
  fi
}

# Get short hash of HEAD commit
#
# Returns:
#   stdout: Short commit hash
get_head_short_hash() {
  git rev-parse --short HEAD 2>/dev/null
}

# Get the last commit message
#
# Returns:
#   stdout: Commit message (first line)
get_last_commit_message() {
  git log -1 --pretty=%s 2>/dev/null
}

# Get list of changed files (staged and unstaged)
#
# Returns:
#   stdout: List of changed files
get_changed_files() {
  git diff --name-only HEAD 2>/dev/null
  git diff --cached --name-only 2>/dev/null
}

# Get the total number of commits on current branch
#
# Returns:
#   stdout: Number of commits
get_total_commits() {
  git rev-list --count HEAD 2>/dev/null || echo "0"
}
