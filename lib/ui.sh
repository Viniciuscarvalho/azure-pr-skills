#!/usr/bin/env bash
# File: ~/.claude/skills/azure-devops-pr/lib/ui.sh
# Interactive UI Components for Azure DevOps PR Automation Skill
# This module handles all user interaction: prompts, selection, and formatted output.
# Designed to be accessible (screen-reader friendly, no color dependencies).

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Title truncation length for display
: "${UI_TITLE_MAX_LENGTH:=60}"

# Load config module for environment variables if not already loaded
if ! type -t debug &>/dev/null; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  if [[ -f "${SCRIPT_DIR}/config.sh" ]]; then
    source "${SCRIPT_DIR}/config.sh"
  fi
fi

# Load git-utils if needed
if ! type -t create_feature_branch &>/dev/null; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  if [[ -f "${SCRIPT_DIR}/git-utils.sh" ]]; then
    source "${SCRIPT_DIR}/git-utils.sh"
  fi
fi

# ==============================================================================
# FORMATTING HELPERS
# ==============================================================================

# Truncate a string to a maximum length with ellipsis
# Args: $1 = string, $2 = max length (optional, default: UI_TITLE_MAX_LENGTH)
# Returns: Truncated string
truncate_string() {
  local str="$1"
  local max_len="${2:-$UI_TITLE_MAX_LENGTH}"
  
  if [[ ${#str} -gt $max_len ]]; then
    echo "${str:0:$((max_len-3))}..."
  else
    echo "$str"
  fi
}

# Print a horizontal separator line
# Args: $1 = character (optional, default: ─), $2 = length (optional, default: 60)
print_separator() {
  local char="${1:-─}"
  local length="${2:-60}"
  printf '%*s\n' "$length" '' | tr ' ' "$char"
}

# Print a blank line
print_blank() {
  echo ""
}

# Format a Work Item type with brackets
# Args: $1 = Work Item type
# Returns: Formatted type (e.g., "[Bug]")
format_work_item_type() {
  local type="$1"
  echo "[$type]"
}

# ==============================================================================
# LOGGING FUNCTIONS (if not already defined)
# ==============================================================================

# These may already be defined in config.sh, but we define them here as fallback

if ! type -t info &>/dev/null; then
  info() { echo "ℹ️  $*"; }
fi

if ! type -t warn &>/dev/null; then
  warn() { echo "⚠️  $*" >&2; }
fi

if ! type -t error &>/dev/null; then
  error() { echo "❌ $*" >&2; }
fi

if ! type -t success &>/dev/null; then
  success() { echo "✓ $*"; }
fi

if ! type -t debug &>/dev/null; then
  debug() {
    if [[ "${AZURE_DEVOPS_DEBUG:-false}" == "true" ]]; then
      echo "[DEBUG] $*" >&2
    fi
  }
fi

# ==============================================================================
# LOADING INDICATORS
# ==============================================================================

# Show a simple loading message
# Args: $1 = message
show_loading() {
  local message="${1:-Loading...}"
  echo "⏳ ${message}" >&2
}

# Show completion of a loading state
# Args: $1 = message
show_loading_done() {
  local message="${1:-Done}"
  echo "✓ ${message}" >&2
}

# Show step progress (e.g., "Step 1/5: Loading Work Items")
# Args: $1 = current step, $2 = total steps, $3 = message
show_step() {
  local current="$1"
  local total="$2"
  local message="$3"
  echo "[${current}/${total}] ${message}" >&2
}

# ==============================================================================
# WORK ITEM DISPLAY
# ==============================================================================

# Display Work Items in a formatted list for selection
# Args: $1 = JSON with work items (batch response from get_work_items_batch)
# Returns (stdout): Selected Work Item ID
# Returns (exit): 0 on success, 1 on invalid selection, 2 if no items
#
# Example:
#   selected_id=$(prompt_work_item_selection "$work_items_json")
prompt_work_item_selection() {
  local work_items_json="$1"
  
  # Check if we have work items
  local count
  count=$(echo "$work_items_json" | jq -r '.value | length' 2>/dev/null || echo "0")
  
  if [[ "$count" == "0" || "$count" == "null" ]]; then
    # Try alternative format (direct array)
    count=$(echo "$work_items_json" | jq -r 'if type == "array" then length else 0 end' 2>/dev/null || echo "0")
  fi
  
  if [[ "$count" == "0" ]]; then
    error "No Work Items found"
    echo "   → Check that you have Work Items assigned in Azure Boards" >&2
    echo "   → Verify AZURE_DEVOPS_PROJECT is correct: ${AZURE_DEVOPS_PROJECT:-not set}" >&2
    return 2
  fi
  
  print_blank >&2
  echo "📋 Your Active Work Items:" >&2
  print_blank >&2
  
  local ids=()
  local index=1
  
  # Parse Work Items - handle both batch response format and array format
  local items_array
  items_array=$(echo "$work_items_json" | jq -c '.value // .' 2>/dev/null)
  
  while IFS= read -r wi; do
    local id type title state
    
    id=$(echo "$wi" | jq -r '.id')
    type=$(echo "$wi" | jq -r '.fields["System.WorkItemType"] // "Item"')
    title=$(echo "$wi" | jq -r '.fields["System.Title"] // "No title"')
    state=$(echo "$wi" | jq -r '.fields["System.State"] // "Unknown"')
    
    # Skip if no valid ID
    if [[ -z "$id" || "$id" == "null" ]]; then
      continue
    fi
    
    ids+=("$id")
    
    # Truncate title for display
    local display_title
    display_title=$(truncate_string "$title" 50)
    
    # Format: [1] #12345 [Bug] - Fix login issue (Active)
    printf "  [%d] #%s [%s] - %s (%s)\n" \
      "$index" "$id" "$type" "$display_title" "$state" >&2
    
    index=$((index + 1))
  done < <(echo "$items_array" | jq -c '.[]' 2>/dev/null)
  
  # Check if we got any valid IDs
  if [[ ${#ids[@]} -eq 0 ]]; then
    error "Could not parse Work Items"
    return 2
  fi
  
  print_blank >&2
  
  # Prompt for selection
  local selection
  read -r -p "Select Work Item (1-${#ids[@]}): " selection
  
  # Validate selection
  if [[ -z "$selection" ]]; then
    error "No selection made"
    echo "   → Please enter a number between 1 and ${#ids[@]}" >&2
    return 1
  fi
  
  if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
    error "Invalid selection: '$selection' is not a number"
    echo "   → Please enter a number between 1 and ${#ids[@]}" >&2
    return 1
  fi
  
  if [[ "$selection" -lt 1 || "$selection" -gt "${#ids[@]}" ]]; then
    error "Selection out of range: $selection"
    echo "   → Please enter a number between 1 and ${#ids[@]}" >&2
    return 1
  fi
  
  # Return selected Work Item ID (array is 0-indexed)
  echo "${ids[$((selection-1))]}"
}

# Display a single Work Item summary
# Args: $1 = Work Item JSON
display_work_item_summary() {
  local wi_json="$1"
  
  local id type title state
  id=$(echo "$wi_json" | jq -r '.id')
  type=$(echo "$wi_json" | jq -r '.fields["System.WorkItemType"] // "Item"')
  title=$(echo "$wi_json" | jq -r '.fields["System.Title"] // "No title"')
  state=$(echo "$wi_json" | jq -r '.fields["System.State"] // "Unknown"')
  
  print_blank >&2
  echo "📌 Selected Work Item:" >&2
  echo "   ID:    #${id}" >&2
  echo "   Type:  ${type}" >&2
  echo "   Title: ${title}" >&2
  echo "   State: ${state}" >&2
  print_blank >&2
}

# ==============================================================================
# BRANCH CREATION PROMPT
# ==============================================================================

# Prompt user to select target branch for the Pull Request
# Returns (stdout): Target branch name
# Returns (exit): 0 on success, 1 on error
#
# Example:
#   target_branch=$(prompt_target_branch_selection)
prompt_target_branch_selection() {
  print_blank >&2
  echo "🎯 Target Branch Selection:" >&2
  print_blank >&2

  # Get default branch as suggestion
  local default_branch
  default_branch=$(get_default_branch 2>/dev/null || echo "main")

  # Fetch available branches from remote
  local branches
  branches=$(git branch -r | grep -v 'HEAD' | sed 's/origin\///' | sed 's/^[[:space:]]*//' | sort -u 2>/dev/null || echo "")

  if [[ -n "$branches" ]]; then
    echo "   Available branches:" >&2
    echo "$branches" | head -10 | while IFS= read -r branch; do
      if [[ "$branch" == "$default_branch" ]]; then
        echo "   - $branch (default)" >&2
      else
        echo "   - $branch" >&2
      fi
    done
    print_blank >&2
  fi

  local target_branch
  read -r -p "Enter target branch [${default_branch}]: " target_branch

  # Use default if empty
  target_branch="${target_branch:-$default_branch}"

  # Validate branch name
  if [[ -z "$target_branch" ]]; then
    error "Target branch cannot be empty"
    return 1
  fi

  debug "Selected target branch: ${target_branch}"
  echo "$target_branch"
}

# Prompt user to create a new branch or use the current one
# Args: $1 = Work Item JSON
# Returns (stdout): Branch name
# Returns (exit): 0 on success, 1 on error, 4 on user cancel
#
# Example:
#   branch_name=$(handle_branch_creation "$wi_json")
handle_branch_creation() {
  local wi_data="$1"

  print_blank >&2
  echo "🔀 Branch Options:" >&2
  echo "   new     - Create a new feature branch from this Work Item" >&2
  echo "   current - Use the current branch (must have commits ahead)" >&2
  print_blank >&2

  local choice
  read -r -p "Create new branch or use current? [new/current]: " choice

  # Default to current if empty
  choice="${choice:-current}"

  case "$choice" in
    new|n)
      local wi_id wi_title
      wi_id=$(echo "$wi_data" | jq -r '.id')
      wi_title=$(echo "$wi_data" | jq -r '.fields["System.Title"] // "feature"')

      if [[ -z "$wi_id" || "$wi_id" == "null" ]]; then
        error "Could not extract Work Item ID"
        return 1
      fi

      create_feature_branch "$wi_id" "$wi_title"
      ;;
    current|c|"")
      validate_current_branch
      ;;
    *)
      error "Invalid choice: '$choice'"
      echo "   → Please enter 'new' or 'current'" >&2
      return 1
      ;;
  esac
}

# Non-interactive version for scripting
# Args: $1 = Work Item JSON, $2 = choice ("new" or "current")
handle_branch_creation_noninteractive() {
  local wi_data="$1"
  local choice="${2:-current}"
  
  case "$choice" in
    new)
      local wi_id wi_title
      wi_id=$(echo "$wi_data" | jq -r '.id')
      wi_title=$(echo "$wi_data" | jq -r '.fields["System.Title"] // "feature"')
      create_feature_branch_noninteractive "$wi_id" "$wi_title"
      ;;
    current|*)
      validate_current_branch
      ;;
  esac
}

# ==============================================================================
# SUCCESS DISPLAY
# ==============================================================================

# Display success message with PR details
# Args: $1 = PR ID, $2 = Work Item ID, $3 = Repository name (optional)
# Outputs formatted success message to stderr
display_success() {
  local pr_id="$1"
  local wi_id="$2"
  local repo_name="${3:-}"
  
  # Get repository name if not provided
  if [[ -z "$repo_name" ]]; then
    repo_name=$(get_repository_name 2>/dev/null || echo "repo")
  fi
  
  # Construct PR URL
  local pr_url="https://dev.azure.com/${AZURE_DEVOPS_ORG}/${AZURE_DEVOPS_PROJECT}/_git/${repo_name}/pullrequest/${pr_id}"
  
  print_blank >&2
  print_separator "─" 60 >&2
  print_blank >&2
  echo "✓ Work Item #${wi_id} loaded" >&2
  echo "✓ Branch validated" >&2
  echo "✓ Pull Request created (Draft)" >&2
  echo "✓ Linked to Work Item #${wi_id}" >&2
  
  if [[ -n "${AZURE_DEVOPS_REVIEWERS:-}" ]]; then
    echo "✓ Reviewers added" >&2
  fi
  
  print_blank >&2
  print_separator "─" 60 >&2
  print_blank >&2
  echo "🎉 PR created successfully!" >&2
  print_blank >&2
  echo "   ${pr_url}" >&2
  print_blank >&2
  print_separator "─" 60 >&2
  
  # Also output PR URL to stdout for piping
  echo "$pr_url"
}

# Display error summary with suggestions
# Args: $1 = error type, $2 = error message
display_error() {
  local error_type="$1"
  local error_message="$2"
  
  print_blank >&2
  print_separator "─" 60 >&2
  print_blank >&2
  error "$error_message" >&2
  print_blank >&2
  
  case "$error_type" in
    auth)
      echo "   Suggestions:" >&2
      echo "   → Verify your AZURE_DEVOPS_PAT is valid" >&2
      echo "   → Check that PAT hasn't expired" >&2
      echo "   → Ensure PAT has required scopes: vso.work, vso.code_write, vso.work_write" >&2
      ;;
    network)
      echo "   Suggestions:" >&2
      echo "   → Check your internet connection" >&2
      echo "   → Verify Azure DevOps is accessible" >&2
      ;;
    git)
      echo "   Suggestions:" >&2
      echo "   → Ensure you're in a git repository" >&2
      echo "   → Check that 'origin' remote is configured" >&2
      ;;
    *)
      echo "   → Please check the error message above for details" >&2
      ;;
  esac
  
  print_blank >&2
  print_separator "─" 60 >&2
}

# ==============================================================================
# PROGRESS DISPLAY
# ==============================================================================

# Display a progress checklist
# Args: array of completed steps
display_progress() {
  local -a steps=("$@")
  
  print_blank >&2
  for step in "${steps[@]}"; do
    echo "✓ ${step}" >&2
  done
}

# Display a step as in progress
# Args: $1 = step description
show_in_progress() {
  local step="$1"
  echo "⏳ ${step}..." >&2
}

# Display a step as completed
# Args: $1 = step description
show_completed() {
  local step="$1"
  echo "✓ ${step}" >&2
}

# Display a step as failed
# Args: $1 = step description
show_failed() {
  local step="$1"
  echo "✗ ${step}" >&2
}

# ==============================================================================
# CONFIRMATION PROMPTS
# ==============================================================================

# Ask for yes/no confirmation
# Args: $1 = question, $2 = default (y/n, optional)
# Returns: 0 for yes, 1 for no
confirm() {
  local question="$1"
  local default="${2:-n}"
  
  local prompt
  if [[ "$default" == "y" ]]; then
    prompt="[Y/n]"
  else
    prompt="[y/N]"
  fi
  
  local answer
  read -r -p "${question} ${prompt}: " answer
  
  answer="${answer:-$default}"
  answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
  
  case "$answer" in
    y|yes)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# Clear the current line (for updating loading messages)
clear_line() {
  printf '\r\033[K' >&2
}

# Move cursor up and clear line
clear_previous_line() {
  printf '\033[A\033[K' >&2
}

# Print a message with a colored indicator (if terminal supports)
# Args: $1 = indicator type (info/warn/error/success), $2 = message
print_indicator() {
  local type="$1"
  local message="$2"
  
  case "$type" in
    info)    echo "ℹ️  ${message}" ;;
    warn)    echo "⚠️  ${message}" >&2 ;;
    error)   echo "❌ ${message}" >&2 ;;
    success) echo "✓ ${message}" ;;
    *)       echo "${message}" ;;
  esac
}

# Get repository name for URLs (helper function)
# This is a fallback if git-utils is not loaded
if ! type -t get_repository_name &>/dev/null; then
  get_repository_name() {
    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null) || return 1
    
    # Extract repo name from URL
    if [[ "$remote_url" =~ /_git/([^/]+)(\.git)?$ ]]; then
      echo "${BASH_REMATCH[1]%.git}"
    elif [[ "$remote_url" =~ /([^/]+)(\.git)?$ ]]; then
      echo "${BASH_REMATCH[1]%.git}"
    else
      return 1
    fi
  }
fi
