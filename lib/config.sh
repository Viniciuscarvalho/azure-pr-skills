#!/usr/bin/env bash
# File: ~/.claude/skills/azure-devops-pr/lib/config.sh
# Configuration validation module for Azure DevOps PR Automation Skill
# This module validates environment variables before any API calls are made.
# Principle: Fail-fast on misconfiguration.

set -euo pipefail

# ==============================================================================
# REQUIRED ENVIRONMENT VARIABLES
# ==============================================================================
# AZURE_DEVOPS_ORG      - Azure DevOps organization name
# AZURE_DEVOPS_PROJECT  - Project name within the organization
# AZURE_DEVOPS_PAT      - Personal Access Token for authentication
#
# OPTIONAL ENVIRONMENT VARIABLES
# AZURE_DEVOPS_REVIEWERS     - Comma-separated reviewer GUIDs
# AZURE_DEVOPS_TARGET_BRANCH - Override default branch (main/master)
# AZURE_DEVOPS_DEBUG         - Enable debug logging (true/false)
# ==============================================================================

# Minimum PAT length (Azure DevOps PATs are typically 52 characters)
# Using default assignment to allow re-sourcing without errors
: "${MIN_PAT_LENGTH:=20}"

# ==============================================================================
# Logging Functions
# ==============================================================================

# Output informational message
# Args: $1 = message
info() {
  echo "ℹ️  $*"
}

# Output warning message to stderr
# Args: $1 = message
warn() {
  echo "⚠️  $*" >&2
}

# Output error message to stderr
# Args: $1 = message
error() {
  echo "❌ $*" >&2
}

# Output success message
# Args: $1 = message
success() {
  echo "✓ $*"
}

# Output debug message to stderr (only if AZURE_DEVOPS_DEBUG=true)
# Args: $1 = message
# IMPORTANT: Never log sensitive data (PAT, tokens, etc.)
debug() {
  if [[ "${AZURE_DEVOPS_DEBUG:-false}" == "true" ]]; then
    echo "[DEBUG] $*" >&2
  fi
}

# ==============================================================================
# Configuration Validation
# ==============================================================================

# Validate that all required environment variables are set and valid.
# This function implements the fail-fast principle - detect configuration
# problems immediately before making any API calls.
#
# Required variables:
#   - AZURE_DEVOPS_ORG: Organization name
#   - AZURE_DEVOPS_PROJECT: Project name
#   - AZURE_DEVOPS_PAT: Personal Access Token (min 20 chars)
#
# Returns:
#   0 - All required variables are valid
#   1 - One or more required variables are missing or invalid
#
# Example:
#   if validate_environment; then
#     echo "Configuration is valid"
#   else
#     echo "Configuration error"
#     exit 1
#   fi
validate_environment() {
  local has_error=false

  debug "Starting environment validation..."

  # Check AZURE_DEVOPS_ORG
  if [[ -z "${AZURE_DEVOPS_ORG:-}" ]]; then
    error "AZURE_DEVOPS_ORG is required but not set"
    echo "   → Set in ~/.bashrc or ~/.zshrc:" >&2
    echo "     export AZURE_DEVOPS_ORG=\"your-value\"" >&2
    echo "" >&2
    has_error=true
  fi

  # Check AZURE_DEVOPS_PROJECT
  if [[ -z "${AZURE_DEVOPS_PROJECT:-}" ]]; then
    error "AZURE_DEVOPS_PROJECT is required but not set"
    echo "   → Set in ~/.bashrc or ~/.zshrc:" >&2
    echo "     export AZURE_DEVOPS_PROJECT=\"your-value\"" >&2
    echo "" >&2
    has_error=true
  fi

  # Check AZURE_DEVOPS_PAT
  if [[ -z "${AZURE_DEVOPS_PAT:-}" ]]; then
    error "AZURE_DEVOPS_PAT is required but not set"
    echo "   → Set in ~/.bashrc or ~/.zshrc:" >&2
    echo "     export AZURE_DEVOPS_PAT=\"your-value\"" >&2
    echo "" >&2
    has_error=true
  fi

  # If any required variable is missing, exit early
  if [[ "$has_error" == "true" ]]; then
    _print_setup_instructions
    return 1
  fi

  # Validate PAT format (length check - NEVER log the actual value)
  if [[ ${#AZURE_DEVOPS_PAT} -lt ${MIN_PAT_LENGTH} ]]; then
    error "AZURE_DEVOPS_PAT appears invalid (too short)"
    echo "   → Personal Access Tokens are typically 52 characters" >&2
    echo "   → Create a new PAT at:" >&2
    echo "     https://dev.azure.com/${AZURE_DEVOPS_ORG}/_usersSettings/tokens" >&2
    echo "" >&2
    echo "   → Required PAT scopes:" >&2
    echo "     • vso.work (Read Work Items)" >&2
    echo "     • vso.work_write (Link Work Items)" >&2
    echo "     • vso.code_write (Create PRs)" >&2
    return 1
  fi

  # Log optional variables status (for debugging)
  _validate_optional_vars

  debug "Environment validation completed successfully"
  return 0
}

# Validate and log status of optional environment variables.
# This function does not cause validation to fail, only logs warnings.
#
# Optional variables:
#   - AZURE_DEVOPS_REVIEWERS: Comma-separated reviewer GUIDs
#   - AZURE_DEVOPS_TARGET_BRANCH: Override default branch
#   - AZURE_DEVOPS_DEBUG: Enable debug logging
_validate_optional_vars() {
  # Check AZURE_DEVOPS_REVIEWERS
  if [[ -n "${AZURE_DEVOPS_REVIEWERS:-}" ]]; then
    debug "AZURE_DEVOPS_REVIEWERS is set (reviewer auto-assignment enabled)"
  else
    debug "AZURE_DEVOPS_REVIEWERS is not set (no automatic reviewers)"
  fi

  # Check AZURE_DEVOPS_TARGET_BRANCH
  if [[ -n "${AZURE_DEVOPS_TARGET_BRANCH:-}" ]]; then
    debug "AZURE_DEVOPS_TARGET_BRANCH is set to: ${AZURE_DEVOPS_TARGET_BRANCH}"
  else
    debug "AZURE_DEVOPS_TARGET_BRANCH is not set (will auto-detect main/master)"
  fi

  # Check AZURE_DEVOPS_DEBUG
  if [[ "${AZURE_DEVOPS_DEBUG:-false}" == "true" ]]; then
    debug "Debug mode is ENABLED"
  fi
}

# Print setup instructions for first-time users or when configuration is incomplete.
_print_setup_instructions() {
  echo "" >&2
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  echo "  Azure DevOps PR Skill - Setup Required" >&2
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  echo "" >&2
  echo "  Add these to your ~/.bashrc or ~/.zshrc:" >&2
  echo "" >&2
  echo "    export AZURE_DEVOPS_ORG=\"your-organization\"" >&2
  echo "    export AZURE_DEVOPS_PROJECT=\"your-project\"" >&2
  echo "    export AZURE_DEVOPS_PAT=\"your-personal-access-token\"" >&2
  echo "" >&2
  echo "  Optional:" >&2
  echo "    export AZURE_DEVOPS_REVIEWERS=\"guid1,guid2\"" >&2
  echo "    export AZURE_DEVOPS_TARGET_BRANCH=\"develop\"" >&2
  echo "    export AZURE_DEVOPS_DEBUG=\"true\"" >&2
  echo "" >&2
  echo "  Create PAT at:" >&2
  echo "    https://dev.azure.com/YOUR_ORG/_usersSettings/tokens" >&2
  echo "" >&2
  echo "  Required PAT scopes:" >&2
  echo "    • vso.work (Read Work Items)" >&2
  echo "    • vso.work_write (Link Work Items)" >&2
  echo "    • vso.code_write (Create PRs)" >&2
  echo "" >&2
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
}

# Get configuration value with default fallback.
# Useful for optional variables.
#
# Args:
#   $1 - Variable name
#   $2 - Default value (optional)
#
# Returns:
#   The value of the variable or the default
#
# Example:
#   target_branch=$(get_config "AZURE_DEVOPS_TARGET_BRANCH" "main")
get_config() {
  local var_name="$1"
  local default_value="${2:-}"
  local var_value
  
  # Use eval for portable indirect variable expansion (works in bash and zsh)
  eval "var_value=\"\${${var_name}:-}\""
  
  if [[ -n "$var_value" ]]; then
    echo "$var_value"
  else
    echo "$default_value"
  fi
}

# Check if debug mode is enabled.
# Returns 0 (true) if debug is enabled, 1 (false) otherwise.
is_debug_enabled() {
  [[ "${AZURE_DEVOPS_DEBUG:-false}" == "true" ]]
}

# Get the Azure DevOps base URL for the configured organization and project.
# Returns: URL string (e.g., https://dev.azure.com/org/project)
get_azure_base_url() {
  echo "https://dev.azure.com/${AZURE_DEVOPS_ORG}/${AZURE_DEVOPS_PROJECT}"
}

# Get the PAT settings URL for the configured organization.
# Returns: URL string for PAT management page
get_pat_settings_url() {
  echo "https://dev.azure.com/${AZURE_DEVOPS_ORG}/_usersSettings/tokens"
}
