#!/usr/bin/env bash
# File: ~/.claude/skills/azure-devops-pr/azure-pr.sh
# Azure DevOps PR Automation Skill - Main Orchestrator
# 
# This script coordinates the entire Pull Request creation workflow:
# 1. Validate environment and git repository
# 2. Fetch and select Work Item
# 3. Handle branch creation/validation
# 4. Create Pull Request with Work Item data
# 5. Link PR to Work Item
# 6. Add reviewers (if configured)
#
# Exit Codes:
#   0: Success - PR created successfully
#   1: Configuration error (missing env vars)
#   2: Git repository error
#   3: Azure DevOps API error
#   4: User cancellation
#
# Usage:
#   ./azure-pr.sh
#
# Prerequisites:
#   - AZURE_DEVOPS_ORG: Your Azure DevOps organization
#   - AZURE_DEVOPS_PROJECT: Your project name
#   - AZURE_DEVOPS_PAT: Personal Access Token
#   - Must be run from within a git repository

set -euo pipefail

# ==============================================================================
# SCRIPT INITIALIZATION
# ==============================================================================

# Get the directory where this script is located
# Use unique variable name to avoid overwriting by sourced modules
_AZURE_PR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all library modules
source "${_AZURE_PR_DIR}/lib/config.sh"
source "${_AZURE_PR_DIR}/lib/azure-client.sh"
source "${_AZURE_PR_DIR}/lib/git-utils.sh"
source "${_AZURE_PR_DIR}/lib/ui.sh"

# ==============================================================================
# EXIT CODES
# ==============================================================================

readonly EXIT_SUCCESS=0
readonly EXIT_CONFIG_ERROR=1
readonly EXIT_GIT_ERROR=2
readonly EXIT_API_ERROR=3
readonly EXIT_USER_CANCEL=4

# ==============================================================================
# MAIN WORKFLOW FUNCTIONS
# ==============================================================================

# Run pre-flight checks before any operations
# Returns: exit code based on check results
run_preflight_checks() {
  show_step 1 6 "Validating environment..."
  
  if ! validate_environment; then
    return $EXIT_CONFIG_ERROR
  fi
  show_completed "Environment validated"
  
  show_step 2 6 "Validating git repository..."
  
  if ! validate_git_repo; then
    return $EXIT_GIT_ERROR
  fi
  show_completed "Git repository validated"
  
  return 0
}

# Fetch Work Items and let user select one
# Returns (stdout): Selected Work Item ID
# Returns (exit): 0 on success, EXIT_API_ERROR or EXIT_USER_CANCEL on failure
fetch_and_select_work_item() {
  show_step 3 6 "Fetching Work Items..."
  
  local wiql_response
  if ! wiql_response=$(fetch_work_items); then
    error "Failed to fetch Work Items"
    return $EXIT_API_ERROR
  fi
  
  # Extract Work Item IDs from WIQL response
  local work_item_ids
  work_item_ids=$(extract_work_item_ids "$wiql_response")
  
  if [[ -z "$work_item_ids" || "$work_item_ids" == "null" ]]; then
    error "No Work Items found assigned to you"
    echo "   → Check that you have Work Items assigned in Azure Boards" >&2
    echo "   → Verify AZURE_DEVOPS_PROJECT is correct: ${AZURE_DEVOPS_PROJECT}" >&2
    return $EXIT_API_ERROR
  fi
  
  debug "Work Item IDs: ${work_item_ids}"
  
  # Get full details for all Work Items (batch request)
  local work_items_details
  if ! work_items_details=$(get_work_items_batch "$work_item_ids"); then
    error "Failed to fetch Work Item details"
    return $EXIT_API_ERROR
  fi
  
  show_completed "Work Items fetched"
  
  # Prompt user to select a Work Item
  local selected_id
  if ! selected_id=$(prompt_work_item_selection "$work_items_details"); then
    # User cancelled or invalid selection
    return $EXIT_USER_CANCEL
  fi
  
  debug "Selected Work Item ID: ${selected_id}"
  echo "$selected_id"
}

# Get full details for a specific Work Item
# Args: $1 = Work Item ID
# Returns (stdout): Work Item JSON with all fields
get_selected_work_item_details() {
  local wi_id="$1"
  
  debug "Fetching full details for Work Item #${wi_id}..."
  
  local wi_details
  if ! wi_details=$(get_work_item_details "$wi_id"); then
    error "Failed to fetch Work Item #${wi_id} details"
    return $EXIT_API_ERROR
  fi
  
  echo "$wi_details"
}

# Handle branch selection (new or current)
# Args: $1 = Work Item JSON
# Returns (stdout): Branch name
handle_branch_selection() {
  local wi_data="$1"
  
  show_step 4 6 "Branch selection..."
  
  local branch_name
  if ! branch_name=$(handle_branch_creation "$wi_data"); then
    return $EXIT_USER_CANCEL
  fi
  
  show_completed "Branch: ${branch_name}"
  echo "$branch_name"
}

# Build PR payload from Work Item data (using azure-client's function)
# Args: $1 = Work Item JSON, $2 = Branch name, $3 = Work Item ID
# Returns (stdout): PR payload JSON
build_pr_payload_from_wi() {
  local wi_data="$1"
  local branch_name="$2"
  local wi_id="$3"

  # Get target branch (use override, prompt user, or detect default)
  local target_branch
  if [[ -n "${AZURE_DEVOPS_TARGET_BRANCH:-}" ]]; then
    target_branch="${AZURE_DEVOPS_TARGET_BRANCH}"
    debug "Using configured target branch: ${target_branch}"
  else
    # Prompt user to select target branch
    if ! target_branch=$(prompt_target_branch_selection); then
      error "Failed to get target branch"
      return $EXIT_USER_CANCEL
    fi
  fi

  debug "Target branch: ${target_branch}"

  # Use the build_pr_payload function from azure-client.sh
  build_pr_payload "$wi_data" "$branch_name" "$target_branch" "$wi_id"
}

# Create the Pull Request
# Args: $1 = PR payload JSON
# Returns (stdout): PR response JSON
create_pr() {
  local pr_payload="$1"
  
  show_step 5 6 "Creating Pull Request..."
  
  # First, ensure branch is pushed to origin
  local current_branch
  current_branch=$(get_current_branch)
  
  if ! is_branch_pushed; then
    show_in_progress "Pushing branch to origin"
    if ! push_current_branch > /dev/null 2>&1; then
      error "Failed to push branch to origin"
      echo "   → Ensure you have push permissions" >&2
      return $EXIT_GIT_ERROR
    fi
    show_completed "Branch pushed"
  fi
  
  # Create the PR
  local pr_response
  if ! pr_response=$(create_pull_request "$pr_payload"); then
    error "Failed to create Pull Request"
    return $EXIT_API_ERROR
  fi
  
  show_completed "Pull Request created (Draft)"
  echo "$pr_response"
}

# Link Work Item to PR and add reviewers
# Args: $1 = Work Item ID, $2 = PR ID, $3 = Repository ID (optional)
finalize_pr() {
  local wi_id="$1"
  local pr_id="$2"
  local repo_id="${3:-}"
  
  show_step 6 6 "Finalizing..."
  
  # Link Work Item to PR
  show_in_progress "Linking to Work Item #${wi_id}"
  if ! link_work_item_to_pr "$wi_id" "$pr_id" "$repo_id"; then
    warn "Failed to link Work Item to PR (non-critical)"
    # Continue anyway - PR is created, linking is nice-to-have
  else
    show_completed "Linked to Work Item #${wi_id}"
  fi
  
  # Add reviewers if configured
  if [[ -n "${AZURE_DEVOPS_REVIEWERS:-}" ]]; then
    show_in_progress "Adding reviewers"
    if ! add_reviewers_to_pr "$pr_id" "$repo_id"; then
      warn "Failed to add some reviewers (non-critical)"
    else
      show_completed "Reviewers added"
    fi
  fi
  
  return 0
}

# ==============================================================================
# MAIN FUNCTION
# ==============================================================================

# Main entry point - orchestrates entire PR creation workflow
main() {
  print_blank
  echo "🚀 Azure DevOps PR Automation" >&2
  print_separator "─" 50 >&2
  print_blank
  
  # ==== PRE-FLIGHT CHECKS ====
  local preflight_result
  run_preflight_checks
  preflight_result=$?
  if [[ $preflight_result -ne 0 ]]; then
    display_error "config" "Pre-flight checks failed"
    return $preflight_result
  fi
  
  # ==== FETCH AND SELECT WORK ITEM ====
  local selected_wi_id
  local fetch_result
  selected_wi_id=$(fetch_and_select_work_item)
  fetch_result=$?
  if [[ $fetch_result -ne 0 ]]; then
    if [[ $fetch_result -eq $EXIT_USER_CANCEL ]]; then
      info "Operation cancelled by user"
    fi
    return $fetch_result
  fi
  
  # ==== GET FULL WORK ITEM DETAILS ====
  local wi_data
  if ! wi_data=$(get_selected_work_item_details "$selected_wi_id"); then
    return $EXIT_API_ERROR
  fi
  
  # Display selected Work Item summary
  display_work_item_summary "$wi_data"
  
  # ==== HANDLE BRANCH ====
  local branch_name
  if ! branch_name=$(handle_branch_selection "$wi_data"); then
    info "Operation cancelled by user"
    return $EXIT_USER_CANCEL
  fi
  
  # ==== BUILD PR PAYLOAD ====
  print_blank
  show_in_progress "Building Pull Request payload"

  local pr_payload
  if ! pr_payload=$(build_pr_payload_from_wi "$wi_data" "$branch_name" "$selected_wi_id"); then
    error "Failed to build PR payload"
    return $EXIT_API_ERROR
  fi

  debug "PR Payload built successfully"
  show_completed "PR payload ready"
  
  # ==== CREATE PR ====
  local pr_response
  local create_result
  pr_response=$(create_pr "$pr_payload")
  create_result=$?
  if [[ $create_result -ne 0 ]]; then
    return $create_result
  fi
  
  # Extract PR ID from response
  local pr_id
  pr_id=$(get_pr_id_from_response "$pr_response")
  
  if [[ -z "$pr_id" || "$pr_id" == "null" ]]; then
    error "Failed to get PR ID from response"
    return $EXIT_API_ERROR
  fi
  
  debug "PR ID: ${pr_id}"
  
  # ==== FINALIZE (LINK + REVIEWERS) ====
  finalize_pr "$selected_wi_id" "$pr_id"
  
  # ==== SUCCESS ====
  local repo_name
  repo_name=$(get_repository_name 2>/dev/null || echo "repo")
  
  display_success "$pr_id" "$selected_wi_id" "$repo_name"
  
  return $EXIT_SUCCESS
}

# ==============================================================================
# SCRIPT ENTRY POINT
# ==============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit $?
fi
