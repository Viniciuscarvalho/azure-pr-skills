#!/usr/bin/env bash
# File: ~/.claude/skills/azure-devops-pr/lib/azure-client.sh
# Azure DevOps REST API v7.2 Client
# This module provides reusable functions for interacting with Azure DevOps API.
# Includes retry logic with exponential backoff for resilience.

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# API Configuration
# Note: Azure DevOps API v7.2+ requires the -preview suffix
# Default to 7.1 (stable) or use 7.2-preview for latest features
: "${AZURE_API_VERSION:=7.1}"
: "${AZURE_API_TIMEOUT:=30}"
: "${AZURE_API_CONNECT_TIMEOUT:=10}"
: "${AZURE_API_MAX_RETRIES:=3}"

# Load config module for logging functions if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! type -t error &>/dev/null; then
  source "${SCRIPT_DIR}/config.sh"
fi

# ==============================================================================
# INTERNAL HELPER FUNCTIONS
# ==============================================================================

# Get Base64 encoded authorization header value
# IMPORTANT: The actual PAT is NEVER logged
# Returns: Base64 encoded string for Basic Auth
_get_auth_header() {
  echo -n ":${AZURE_DEVOPS_PAT}" | base64
}

# Get base URL for Azure DevOps API
# Returns: URL string (e.g., https://dev.azure.com/org/project)
_get_base_url() {
  echo "https://dev.azure.com/${AZURE_DEVOPS_ORG}/${AZURE_DEVOPS_PROJECT}"
}

# Log a debug message for API calls (with PAT redaction)
# Args: $1 = method, $2 = url
_log_api_call() {
  local method="$1"
  local url="$2"
  debug "API Call: ${method} ${url}"
  debug "Authorization: Basic [REDACTED]"
}

# Parse HTTP response to extract body and status code
# Args: $1 = raw response (body + newline + status_code)
# Sets: _RESPONSE_BODY, _RESPONSE_CODE
_parse_response() {
  local raw_response="$1"
  _RESPONSE_CODE=$(echo "$raw_response" | tail -n 1)
  _RESPONSE_BODY=$(echo "$raw_response" | sed '$d')
}

# ==============================================================================
# CORE API FUNCTION
# ==============================================================================

# Generic Azure DevOps API caller with retry logic
# Implements exponential backoff for rate limiting (429) and service unavailable (503)
#
# Args:
#   $1 - HTTP method (GET, POST, PATCH, DELETE)
#   $2 - API path (e.g., /_apis/wit/wiql)
#   $3 - JSON body (optional)
#
# Returns:
#   stdout: JSON response body on success
#   exit code: 0 on success, 1 on failure
#
# Example:
#   response=$(azure_api_call "GET" "/_apis/git/repositories?api-version=7.2")
#   response=$(azure_api_call "POST" "/_apis/wit/wiql?api-version=7.2" "$json_body")
azure_api_call() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  
  local base_url
  base_url=$(_get_base_url)
  local url="${base_url}${path}"
  
  local auth_header
  auth_header=$(_get_auth_header)
  
  local retry_delay=1
  local attempt
  
  _log_api_call "$method" "$url"
  
  for attempt in $(seq 1 $AZURE_API_MAX_RETRIES); do
    local raw_response
    local curl_exit_code=0
    
    # Build curl command
    local curl_args=(
      -s                                          # Silent mode
      -w "\n%{http_code}"                        # Append HTTP status code
      --connect-timeout "$AZURE_API_CONNECT_TIMEOUT"
      --max-time "$AZURE_API_TIMEOUT"
      -X "$method"
      -H "Authorization: Basic ${auth_header}"
      -H "Content-Type: application/json"
      -H "Accept: application/json"
    )
    
    # Add body for POST/PATCH/PUT requests
    if [[ -n "$body" && "$method" != "GET" && "$method" != "DELETE" ]]; then
      curl_args+=(-d "$body")
    fi
    
    curl_args+=("$url")
    
    # Execute curl
    raw_response=$(curl "${curl_args[@]}" 2>/dev/null) || curl_exit_code=$?
    
    # Handle curl errors (network issues)
    if [[ $curl_exit_code -ne 0 ]]; then
      debug "curl failed with exit code $curl_exit_code (attempt $attempt/$AZURE_API_MAX_RETRIES)"
      if [[ $attempt -lt $AZURE_API_MAX_RETRIES ]]; then
        debug "Retrying in ${retry_delay}s..."
        sleep $retry_delay
        retry_delay=$((retry_delay * 2))
        continue
      fi
      error "Network error: Failed to connect to Azure DevOps API"
      echo "   → Check your internet connection" >&2
      echo "   → Verify ${AZURE_DEVOPS_ORG} is a valid organization" >&2
      return 1
    fi
    
    # Parse response
    _parse_response "$raw_response"
    
    debug "Response HTTP ${_RESPONSE_CODE} (attempt $attempt)"
    
    case "$_RESPONSE_CODE" in
      200|201|204)
        # Success
        echo "$_RESPONSE_BODY"
        return 0
        ;;
      
      429)
        # Rate limited - retry with backoff
        if [[ $attempt -lt $AZURE_API_MAX_RETRIES ]]; then
          warn "Rate limited (HTTP 429), retrying in ${retry_delay}s... (attempt $attempt/$AZURE_API_MAX_RETRIES)"
          sleep $retry_delay
          retry_delay=$((retry_delay * 2))
          continue
        fi
        error "Rate limited by Azure DevOps API after $AZURE_API_MAX_RETRIES attempts"
        echo "   → Wait a few minutes and try again" >&2
        echo "   → Consider reducing request frequency" >&2
        return 1
        ;;
      
      503)
        # Service unavailable - retry with backoff
        if [[ $attempt -lt $AZURE_API_MAX_RETRIES ]]; then
          warn "Service unavailable (HTTP 503), retrying in ${retry_delay}s... (attempt $attempt/$AZURE_API_MAX_RETRIES)"
          sleep $retry_delay
          retry_delay=$((retry_delay * 2))
          continue
        fi
        error "Azure DevOps service unavailable after $AZURE_API_MAX_RETRIES attempts"
        echo "   → Check Azure DevOps status: https://status.dev.azure.com" >&2
        return 1
        ;;
      
      401)
        # Authentication failed - don't retry
        error "Authentication failed (HTTP 401)"
        echo "   → Ensure PAT has required scopes: vso.work, vso.code_write, vso.work_write" >&2
        echo "   → Verify PAT hasn't expired at: https://dev.azure.com/${AZURE_DEVOPS_ORG}/_usersSettings/tokens" >&2
        return 1
        ;;
      
      403)
        # Forbidden - insufficient permissions
        error "Access forbidden (HTTP 403)"
        echo "   → Your PAT doesn't have permission for this operation" >&2
        echo "   → Required scopes: vso.work, vso.code_write, vso.work_write" >&2
        return 1
        ;;
      
      404)
        # Not found
        error "Resource not found (HTTP 404)"
        echo "   → Verify AZURE_DEVOPS_ORG: ${AZURE_DEVOPS_ORG}" >&2
        echo "   → Verify AZURE_DEVOPS_PROJECT: ${AZURE_DEVOPS_PROJECT}" >&2
        return 1
        ;;
      
      400)
        # Bad request
        local error_msg
        error_msg=$(echo "$_RESPONSE_BODY" | jq -r '.message // .errorMessage // "Unknown error"' 2>/dev/null || echo "Bad request")
        error "Bad request (HTTP 400): $error_msg"
        return 1
        ;;
      
      *)
        # Other errors
        local error_detail
        error_detail=$(echo "$_RESPONSE_BODY" | jq -r '.message // .errorMessage // empty' 2>/dev/null || echo "")
        if [[ -n "$error_detail" ]]; then
          error "API error (HTTP $_RESPONSE_CODE): $error_detail"
        else
          error "API error (HTTP $_RESPONSE_CODE)"
        fi
        return 1
        ;;
    esac
  done
  
  # Should not reach here, but just in case
  error "API call failed after $AZURE_API_MAX_RETRIES attempts"
  return 1
}

# ==============================================================================
# WORK ITEM FUNCTIONS
# ==============================================================================

# Fetch Work Items assigned to current user
# Uses WIQL (Work Item Query Language) to query active items
#
# Returns:
#   stdout: JSON object with workItems array (contains id and url for each item)
#   exit code: 0 on success, 1 on failure
#
# Note: This returns only IDs; use get_work_item_details() to get full fields
fetch_work_items() {
  local wiql_query
  
  # Build WIQL query for Work Items assigned to current user
  # States: Active, New, In Progress (common active states)
  wiql_query=$(cat <<-'EOF'
{
  "query": "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State] FROM WorkItems WHERE [System.AssignedTo] = @Me AND [System.State] IN ('Active', 'New', 'In Progress', 'To Do', 'Doing') ORDER BY [System.ChangedDate] DESC"
}
EOF
)
  
  debug "Fetching Work Items assigned to current user..."
  azure_api_call "POST" "/_apis/wit/wiql?api-version=${AZURE_API_VERSION}" "$wiql_query"
}

# Get detailed information for a specific Work Item
# Retrieves all fields including description, acceptance criteria, and tags
#
# Args:
#   $1 - Work Item ID
#
# Returns:
#   stdout: JSON object with full Work Item fields
#   exit code: 0 on success, 1 on failure
get_work_item_details() {
  local wi_id="$1"
  
  if [[ -z "$wi_id" ]]; then
    error "Work Item ID is required"
    return 1
  fi
  
  debug "Fetching details for Work Item #${wi_id}..."
  
  # Request specific fields we need for PR creation
  local fields="System.Id,System.WorkItemType,System.Title,System.State,System.Description,System.Tags,Microsoft.VSTS.Common.AcceptanceCriteria"
  
  azure_api_call "GET" "/_apis/wit/workitems/${wi_id}?\$expand=all&api-version=${AZURE_API_VERSION}"
}

# Get details for multiple Work Items in a single request (batch)
# More efficient than multiple get_work_item_details() calls
#
# Args:
#   $1 - Comma-separated list of Work Item IDs (e.g., "123,456,789")
#
# Returns:
#   stdout: JSON object with value array containing Work Items
#   exit code: 0 on success, 1 on failure
get_work_items_batch() {
  local ids="$1"
  
  if [[ -z "$ids" ]]; then
    error "Work Item IDs are required"
    return 1
  fi
  
  debug "Fetching batch details for Work Items: ${ids}..."
  azure_api_call "GET" "/_apis/wit/workitems?ids=${ids}&\$expand=all&api-version=${AZURE_API_VERSION}"
}

# ==============================================================================
# REPOSITORY FUNCTIONS
# ==============================================================================

# Get repository ID from the git remote URL
# Parses the origin remote to extract repository name, then looks up ID via API
#
# Returns:
#   stdout: Repository ID (GUID)
#   exit code: 0 on success, 1 on failure
get_repository_id() {
  local remote_url
  local repo_name
  
  # Get remote URL from git
  if ! remote_url=$(git remote get-url origin 2>/dev/null); then
    error "Failed to get git remote URL"
    echo "   → Ensure you're in a git repository with 'origin' remote" >&2
    return 1
  fi
  
  debug "Remote URL: ${remote_url}"
  
  # Extract repository name from URL
  # Handles both HTTPS and SSH formats:
  # - https://dev.azure.com/org/project/_git/repo
  # - https://org@dev.azure.com/org/project/_git/repo
  # - git@ssh.dev.azure.com:v3/org/project/repo
  # - org@vs-ssh.visualstudio.com:v3/org/project/repo
  
  if [[ "$remote_url" =~ /_git/([^/]+)(\.git)?$ ]]; then
    # HTTPS format
    repo_name="${BASH_REMATCH[1]}"
  elif [[ "$remote_url" =~ :v3/[^/]+/[^/]+/([^/]+)(\.git)?$ ]]; then
    # SSH format
    repo_name="${BASH_REMATCH[1]}"
  else
    error "Could not parse repository name from remote URL"
    echo "   → Remote URL: ${remote_url}" >&2
    echo "   → Expected format: https://dev.azure.com/org/project/_git/repo" >&2
    return 1
  fi
  
  # Remove .git suffix if present
  repo_name="${repo_name%.git}"
  
  debug "Repository name: ${repo_name}"
  
  # Look up repository by name to get ID
  local response
  if ! response=$(azure_api_call "GET" "/_apis/git/repositories/${repo_name}?api-version=${AZURE_API_VERSION}"); then
    return 1
  fi
  
  # Extract repository ID
  local repo_id
  repo_id=$(echo "$response" | jq -r '.id // empty')
  
  if [[ -z "$repo_id" ]]; then
    error "Could not find repository ID for '${repo_name}'"
    return 1
  fi
  
  debug "Repository ID: ${repo_id}"
  echo "$repo_id"
}

# ==============================================================================
# PULL REQUEST FUNCTIONS
# ==============================================================================

# Build PR payload JSON from Work Item data
# Converts Work Item fields into a properly formatted PR creation payload
#
# Args:
#   $1 - Work Item JSON (full details from get_work_item_details)
#   $2 - Source branch name (e.g., "feature/WI-123-my-feature")
#   $3 - Target branch name (e.g., "main")
#   $4 - Work Item ID
#
# Returns:
#   stdout: JSON payload for PR creation
build_pr_payload() {
  local wi_json="$1"
  local source_branch="$2"
  local target_branch="$3"
  local wi_id="${4:-}"

  # Extract Work Item fields
  local wi_type
  local wi_title
  local wi_description
  local wi_acceptance_criteria
  local wi_tags

  # If wi_id not provided, extract from JSON
  if [[ -z "$wi_id" ]]; then
    wi_id=$(echo "$wi_json" | jq -r '.id')
  fi

  wi_type=$(echo "$wi_json" | jq -r '.fields["System.WorkItemType"] // "Item"')
  wi_title=$(echo "$wi_json" | jq -r '.fields["System.Title"] // "No title"')
  wi_description=$(echo "$wi_json" | jq -r '.fields["System.Description"] // ""')
  wi_acceptance_criteria=$(echo "$wi_json" | jq -r '.fields["Microsoft.VSTS.Common.AcceptanceCriteria"] // ""')
  wi_tags=$(echo "$wi_json" | jq -r '.fields["System.Tags"] // ""')

  # Convert HTML description to plain text (basic conversion)
  wi_description=$(echo "$wi_description" | sed -e 's/<br[^>]*>/\n/gi' -e 's/<[^>]*>//g' -e 's/&nbsp;/ /g' -e 's/&amp;/\&/g' -e 's/&lt;/</g' -e 's/&gt;/>/g')

  # Convert acceptance criteria to markdown checklist
  local ac_markdown=""
  if [[ -n "$wi_acceptance_criteria" ]]; then
    # Convert HTML to text first
    ac_markdown=$(echo "$wi_acceptance_criteria" | sed -e 's/<br[^>]*>/\n/gi' -e 's/<[^>]*>//g' -e 's/&nbsp;/ /g' -e 's/&amp;/\&/g' -e 's/&lt;/</g' -e 's/&gt;/>/g')
    # Convert lines to checklist items (if not already)
    ac_markdown=$(echo "$ac_markdown" | while IFS= read -r line; do
      line=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
      if [[ -n "$line" ]]; then
        # Check if line already has checkbox
        if [[ "$line" =~ ^-[[:space:]]*\[[[:space:]]?\] ]]; then
          echo "$line"
        elif [[ "$line" =~ ^[\*\-] ]]; then
          # Convert bullet to checkbox
          echo "- [ ] ${line#*[\*\-] }"
        else
          echo "- [ ] $line"
        fi
      fi
    done)
  fi

  # Build PR title: "WI-{id}: {title}"
  local pr_title="WI-${wi_id}: ${wi_title}"

  # Build PR description with improved markdown formatting (based on checking-pr skill)
  local pr_description="## 📋 Summary

**Work Item**: [#${wi_id}](https://dev.azure.com/${AZURE_DEVOPS_ORG}/${AZURE_DEVOPS_PROJECT}/_workitems/edit/${wi_id}) - ${wi_type}

${wi_description}

## ✅ Acceptance Criteria

${ac_markdown}

## 🧪 Testing Strategy

- [ ] Unit tests added/updated
- [ ] Integration tests verified
- [ ] Manual testing completed
- [ ] Edge cases considered

## 📝 Additional Notes

_Add any relevant context, breaking changes, or migration notes here_

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)"

  # Build labels array from tags
  local labels_json="[]"
  if [[ -n "$wi_tags" ]]; then
    # Tags are semicolon-separated in Azure DevOps
    labels_json=$(echo "$wi_tags" | tr ';' '\n' | while IFS= read -r tag; do
      tag=$(echo "$tag" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
      if [[ -n "$tag" ]]; then
        echo "{\"name\": \"$tag\"}"
      fi
    done | jq -s '.')
  fi

  # Build reviewers array if configured (correct format for Azure DevOps API)
  local reviewers_json="[]"
  if [[ -n "${AZURE_DEVOPS_REVIEWERS:-}" ]]; then
    reviewers_json=$(echo "$AZURE_DEVOPS_REVIEWERS" | tr ',' '\n' | while IFS= read -r reviewer_id; do
      reviewer_id=$(echo "$reviewer_id" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
      if [[ -n "$reviewer_id" ]]; then
        # Correct format: only id field is required for creation
        echo "{\"id\": \"$reviewer_id\"}"
      fi
    done | jq -s '.')
  fi

  # Build workItemRefs array to link Work Item directly in PR creation
  local work_item_refs_json="[]"
  if [[ -n "$wi_id" && "$wi_id" != "null" ]]; then
    work_item_refs_json=$(jq -n --arg id "$wi_id" '[{id: $id}]')
  fi

  # Build final payload with workItemRefs
  jq -n \
    --arg source "refs/heads/${source_branch}" \
    --arg target "refs/heads/${target_branch}" \
    --arg title "$pr_title" \
    --arg description "$pr_description" \
    --argjson labels "$labels_json" \
    --argjson reviewers "$reviewers_json" \
    --argjson workItemRefs "$work_item_refs_json" \
    '{
      sourceRefName: $source,
      targetRefName: $target,
      title: $title,
      description: $description,
      isDraft: true,
      labels: $labels,
      reviewers: $reviewers,
      workItemRefs: $workItemRefs
    }'
}

# Create a Pull Request in Azure DevOps
# Creates a draft PR with the provided payload
#
# Args:
#   $1 - PR payload JSON (from build_pr_payload)
#
# Returns:
#   stdout: Full PR response JSON
#   exit code: 0 on success, 1 on failure
create_pull_request() {
  local pr_payload="$1"
  
  # Get repository ID
  local repo_id
  if ! repo_id=$(get_repository_id); then
    return 1
  fi
  
  debug "Creating Pull Request in repository ${repo_id}..."
  
  local response
  if ! response=$(azure_api_call "POST" "/_apis/git/repositories/${repo_id}/pullrequests?api-version=${AZURE_API_VERSION}" "$pr_payload"); then
    return 1
  fi
  
  echo "$response"
}

# Extract PR ID from PR response
# Helper function to get just the ID from create_pull_request response
#
# Args:
#   $1 - PR response JSON
#
# Returns:
#   stdout: PR ID (integer)
get_pr_id_from_response() {
  local pr_response="$1"
  echo "$pr_response" | jq -r '.pullRequestId'
}

# Get PR URL from PR response
# Helper function to construct the web URL for the PR
#
# Args:
#   $1 - PR response JSON
#
# Returns:
#   stdout: PR web URL
get_pr_url_from_response() {
  local pr_response="$1"
  local pr_id
  local repo_name
  
  pr_id=$(echo "$pr_response" | jq -r '.pullRequestId')
  repo_name=$(echo "$pr_response" | jq -r '.repository.name')
  
  echo "https://dev.azure.com/${AZURE_DEVOPS_ORG}/${AZURE_DEVOPS_PROJECT}/_git/${repo_name}/pullrequest/${pr_id}"
}

# ==============================================================================
# WORK ITEM LINKING
# ==============================================================================

# Link a Work Item to a Pull Request
# Creates an ArtifactLink relationship between the Work Item and PR
#
# Args:
#   $1 - Work Item ID
#   $2 - PR ID
#   $3 - Repository ID (optional, will be fetched if not provided)
#
# Returns:
#   exit code: 0 on success, 1 on failure
link_work_item_to_pr() {
  local wi_id="$1"
  local pr_id="$2"
  local repo_id="${3:-}"
  
  if [[ -z "$wi_id" || -z "$pr_id" ]]; then
    error "Work Item ID and PR ID are required"
    return 1
  fi
  
  # Get repository ID if not provided
  if [[ -z "$repo_id" ]]; then
    if ! repo_id=$(get_repository_id); then
      return 1
    fi
  fi
  
  debug "Linking Work Item #${wi_id} to PR #${pr_id}..."
  
  # Build the artifact link payload
  # The URL format is: vstfs:///Git/PullRequestId/{project_id}%2F{pr_id}
  local project_id
  project_id=$(get_project_id)
  
  local link_payload
  link_payload=$(cat <<EOF
[
  {
    "op": "add",
    "path": "/relations/-",
    "value": {
      "rel": "ArtifactLink",
      "url": "vstfs:///Git/PullRequestId/${project_id}%2F${pr_id}",
      "attributes": {
        "name": "Pull Request"
      }
    }
  }
]
EOF
)
  
  # Use PATCH to update the Work Item
  # Note: Content-Type for PATCH must be application/json-patch+json
  local response
  local auth_header
  auth_header=$(_get_auth_header)
  local url="${AZURE_DEVOPS_ORG}/${AZURE_DEVOPS_PROJECT}/_apis/wit/workitems/${wi_id}?api-version=${AZURE_API_VERSION}"
  local full_url="https://dev.azure.com/${url}"
  
  _log_api_call "PATCH" "$full_url"
  
  response=$(curl -s -w "\n%{http_code}" \
    --connect-timeout "$AZURE_API_CONNECT_TIMEOUT" \
    --max-time "$AZURE_API_TIMEOUT" \
    -X "PATCH" \
    -H "Authorization: Basic ${auth_header}" \
    -H "Content-Type: application/json-patch+json" \
    -H "Accept: application/json" \
    -d "$link_payload" \
    "$full_url" 2>/dev/null) || {
    error "Failed to link Work Item to PR"
    return 1
  }
  
  _parse_response "$response"
  
  case "$_RESPONSE_CODE" in
    200|201)
      debug "Successfully linked Work Item #${wi_id} to PR #${pr_id}"
      return 0
      ;;
    *)
      local error_msg
      error_msg=$(echo "$_RESPONSE_BODY" | jq -r '.message // "Unknown error"' 2>/dev/null || echo "Unknown error")
      error "Failed to link Work Item to PR (HTTP $_RESPONSE_CODE): $error_msg"
      return 1
      ;;
  esac
}

# Get project ID for the configured project
# Needed for creating artifact links
#
# Returns:
#   stdout: Project ID (GUID)
get_project_id() {
  local response
  if ! response=$(azure_api_call "GET" "/_apis/projects/${AZURE_DEVOPS_PROJECT}?api-version=${AZURE_API_VERSION}"); then
    # Fallback: use project name URL-encoded
    echo "${AZURE_DEVOPS_PROJECT}"
    return 0
  fi
  
  local project_id
  project_id=$(echo "$response" | jq -r '.id // empty')
  
  if [[ -z "$project_id" ]]; then
    # Fallback to project name
    echo "${AZURE_DEVOPS_PROJECT}"
  else
    echo "$project_id"
  fi
}

# ==============================================================================
# REVIEWER FUNCTIONS
# ==============================================================================

# Add reviewers to an existing Pull Request
# Only runs if AZURE_DEVOPS_REVIEWERS is configured
#
# Args:
#   $1 - PR ID
#   $2 - Repository ID (optional)
#
# Returns:
#   exit code: 0 on success (or if no reviewers configured), 1 on failure
add_reviewers_to_pr() {
  local pr_id="$1"
  local repo_id="${2:-}"
  
  # Skip if no reviewers configured
  if [[ -z "${AZURE_DEVOPS_REVIEWERS:-}" ]]; then
    debug "No reviewers configured (AZURE_DEVOPS_REVIEWERS not set)"
    return 0
  fi
  
  if [[ -z "$pr_id" ]]; then
    error "PR ID is required"
    return 1
  fi
  
  # Get repository ID if not provided
  if [[ -z "$repo_id" ]]; then
    if ! repo_id=$(get_repository_id); then
      return 1
    fi
  fi
  
  debug "Adding reviewers to PR #${pr_id}..."
  
  # Add each reviewer
  local reviewer_id
  local success=true
  
  for reviewer_id in ${AZURE_DEVOPS_REVIEWERS//,/ }; do
    reviewer_id=$(echo "$reviewer_id" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    
    if [[ -z "$reviewer_id" ]]; then
      continue
    fi
    
    debug "Adding reviewer: ${reviewer_id}"
    
    local reviewer_payload
    reviewer_payload=$(jq -n --arg id "$reviewer_id" '{id: $id, isRequired: false}')
    
    if ! azure_api_call "PUT" \
      "/_apis/git/repositories/${repo_id}/pullrequests/${pr_id}/reviewers/${reviewer_id}?api-version=${AZURE_API_VERSION}" \
      "$reviewer_payload" > /dev/null; then
      warn "Failed to add reviewer ${reviewer_id}"
      success=false
    fi
  done
  
  if [[ "$success" == "true" ]]; then
    debug "All reviewers added successfully"
    return 0
  else
    warn "Some reviewers could not be added"
    return 0  # Non-critical, don't fail
  fi
}

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# Check if Azure DevOps API is reachable
# Useful for pre-flight checks
#
# Returns:
#   exit code: 0 if reachable, 1 if not
check_api_connectivity() {
  debug "Checking Azure DevOps API connectivity..."
  
  if azure_api_call "GET" "/_apis/projects?api-version=${AZURE_API_VERSION}&\$top=1" > /dev/null 2>&1; then
    debug "API connectivity OK"
    return 0
  else
    return 1
  fi
}

# Extract Work Item IDs from WIQL response
# Converts the workItems array to a comma-separated list of IDs
#
# Args:
#   $1 - WIQL response JSON
#
# Returns:
#   stdout: Comma-separated list of IDs (e.g., "123,456,789")
extract_work_item_ids() {
  local wiql_response="$1"
  echo "$wiql_response" | jq -r '[.workItems[].id] | join(",")'
}

# Check if a Work Item ID is valid
#
# Args:
#   $1 - Work Item ID
#
# Returns:
#   exit code: 0 if valid, 1 if not
is_valid_work_item_id() {
  local wi_id="$1"
  [[ "$wi_id" =~ ^[0-9]+$ ]]
}
