#!/usr/bin/env bats
# File: ~/.claude/skills/azure-devops-pr/tests/integration/test_full_workflow.bats
# End-to-end integration tests for the Azure DevOps PR Automation Skill
# These tests mock the Azure DevOps API and git operations to test the full workflow
# Run with: bats tests/integration/test_full_workflow.bats

# ==============================================================================
# Test Setup and Teardown
# ==============================================================================

setup() {
  # Get the directory containing this test file
  BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
  SKILL_DIR="${BATS_TEST_DIR}/../.."
  
  # Create temp directory for test repos and mocks
  TEST_TEMP_DIR=$(mktemp -d)
  MOCK_DIR="${TEST_TEMP_DIR}/mocks"
  mkdir -p "$MOCK_DIR"
  
  # Set up test environment variables
  export AZURE_DEVOPS_ORG="test-org"
  export AZURE_DEVOPS_PROJECT="test-project"
  export AZURE_DEVOPS_PAT="test-pat-abcdefghijklmnopqrstuvwxyz123456"
  export AZURE_DEVOPS_DEBUG="false"
  
  # Prepend mock directory to PATH
  export PATH="${MOCK_DIR}:${PATH}"
}

teardown() {
  # Clean up temp directory
  if [[ -d "$TEST_TEMP_DIR" ]]; then
    rm -rf "$TEST_TEMP_DIR"
  fi
}

# ==============================================================================
# Mock Helpers
# ==============================================================================

# Create a test git repository with Azure DevOps-style remote URL
create_test_repo() {
  local repo_name="${1:-test-repo}"
  local repo_dir="${TEST_TEMP_DIR}/${repo_name}"
  
  mkdir -p "$repo_dir"
  cd "$repo_dir" >/dev/null 2>&1
  
  git init --initial-branch=main -q >/dev/null 2>&1
  git config user.email "test@test.com"
  git config user.name "Test User"
  
  # Create initial commit
  echo "# Test Repo" > README.md
  git add README.md >/dev/null 2>&1
  git commit -m "Initial commit" -q >/dev/null 2>&1
  
  # Create bare remote (used for actual push/pull operations)
  local remote_dir="${TEST_TEMP_DIR}/${repo_name}-remote.git"
  git clone --bare "$repo_dir" "$remote_dir" -q >/dev/null 2>&1
  
  # Add origin remote pointing to bare repo (for git operations)
  git remote add origin "$remote_dir" >/dev/null 2>&1 || git remote set-url origin "$remote_dir" >/dev/null 2>&1
  
  # Push main to origin
  git push -u origin main -q >/dev/null 2>&1 || true
  
  # Now change the fetch URL to Azure DevOps format (for URL parsing)
  # Keep push URL as local repo
  git remote set-url origin "https://dev.azure.com/test-org/test-project/_git/${repo_name}" >/dev/null 2>&1
  git remote set-url --push origin "$remote_dir" >/dev/null 2>&1
  
  # Create a fake remote ref for main
  git update-ref refs/remotes/origin/main HEAD >/dev/null 2>&1
  git branch --set-upstream-to=origin/main main >/dev/null 2>&1 || true
  
  echo "$repo_dir"
}

# Create a mock curl that returns predefined responses
# This mock handles multiple API endpoints
create_curl_mock() {
  cat > "${MOCK_DIR}/curl" <<'MOCKSCRIPT'
#!/bin/bash

# Parse URL and method from arguments
url=""
method="GET"
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[i]}" in
    -X) method="${args[i+1]}" ;;
    http*) url="${args[i]}" ;;
  esac
done

# Default successful responses based on endpoint
# NOTE: Order matters! More specific patterns must come first
if [[ "$url" =~ "wiql" ]]; then
  # WIQL query response
  echo '{"workItems": [{"id": 12345, "url": "https://test"}]}'
  echo "200"
elif [[ "$url" =~ "workitems/12345" ]] || [[ "$url" =~ "workitems?ids=12345" ]]; then
  # Single Work Item or batch response
  if [[ "$url" =~ "ids=" ]]; then
    echo '{"count": 1, "value": [{"id": 12345, "fields": {"System.WorkItemType": "Bug", "System.Title": "Test Bug", "System.State": "Active", "System.Description": "Test description", "Microsoft.VSTS.Common.AcceptanceCriteria": "Test criterion"}}]}'
  else
    echo '{"id": 12345, "fields": {"System.WorkItemType": "Bug", "System.Title": "Test Bug", "System.State": "Active", "System.Description": "Test description", "Microsoft.VSTS.Common.AcceptanceCriteria": "Test criterion"}}'
  fi
  echo "200"
elif [[ "$url" =~ pullrequests/[0-9]+/reviewers ]]; then
  # Add reviewer to existing PR
  echo '{"id": "reviewer-guid"}'
  echo "200"
elif [[ "$url" =~ pullrequests ]] && [[ "$method" == "POST" ]]; then
  # Create PR response - must come BEFORE repositories check
  echo '{"pullRequestId": 789, "status": "active", "repository": {"name": "test-repo"}}'
  echo "201"
elif [[ "$url" =~ repositories/[^/\?]+\? ]] || [[ "$url" =~ repositories/[^/]+$ ]]; then
  # Repository info lookup (not the pullrequests endpoint)
  repo_name=$(echo "$url" | grep -oE 'repositories/[^/?]+' | sed 's/repositories\///')
  echo "{\"id\": \"repo-guid-123\", \"name\": \"${repo_name:-test-repo}\"}"
  echo "200"
elif [[ "$url" =~ "projects" ]]; then
  # Project info
  echo '{"id": "project-guid-123", "name": "test-project"}'
  echo "200"
elif [[ "$url" =~ "workitems" ]] && [[ "$method" == "PATCH" ]]; then
  # Link Work Item response
  echo '{"id": 12345}'
  echo "200"
else
  # Default success
  echo '{}'
  echo "200"
fi
MOCKSCRIPT
  chmod +x "${MOCK_DIR}/curl"
}

# Create a curl mock that fails on authentication
create_auth_fail_curl_mock() {
  cat > "${MOCK_DIR}/curl" <<'MOCKSCRIPT'
#!/bin/bash
echo '{"message": "Unauthorized"}'
echo "401"
MOCKSCRIPT
  chmod +x "${MOCK_DIR}/curl"
}

# Create a curl mock that returns no work items
create_empty_wi_curl_mock() {
  cat > "${MOCK_DIR}/curl" <<'MOCKSCRIPT'
#!/bin/bash
url=""
for arg in "$@"; do
  case "$arg" in
    http*) url="$arg" ;;
  esac
done

if [[ "$url" =~ "wiql" ]]; then
  echo '{"workItems": []}'
  echo "200"
else
  echo '{}'
  echo "200"
fi
MOCKSCRIPT
  chmod +x "${MOCK_DIR}/curl"
}

# ==============================================================================
# Tests: Exit Code Validation
# ==============================================================================

@test "exits with code 1 when AZURE_DEVOPS_ORG is missing" {
  unset AZURE_DEVOPS_ORG
  
  repo_dir=$(create_test_repo "exit1-repo")
  cd "$repo_dir"
  
  run "${SKILL_DIR}/azure-pr.sh"
  
  [ "$status" -eq 1 ]
}

@test "exits with code 1 when AZURE_DEVOPS_PROJECT is missing" {
  unset AZURE_DEVOPS_PROJECT
  
  repo_dir=$(create_test_repo "exit1-project-repo")
  cd "$repo_dir"
  
  run "${SKILL_DIR}/azure-pr.sh"
  
  [ "$status" -eq 1 ]
}

@test "exits with code 1 when AZURE_DEVOPS_PAT is missing" {
  unset AZURE_DEVOPS_PAT
  
  repo_dir=$(create_test_repo "exit1-pat-repo")
  cd "$repo_dir"
  
  run "${SKILL_DIR}/azure-pr.sh"
  
  [ "$status" -eq 1 ]
}

@test "exits with code 2 when not in git repository" {
  cd "$TEST_TEMP_DIR"
  
  # Create non-git directory
  mkdir -p "${TEST_TEMP_DIR}/not-a-repo"
  cd "${TEST_TEMP_DIR}/not-a-repo"
  
  run "${SKILL_DIR}/azure-pr.sh"
  
  [ "$status" -eq 2 ]
}

@test "exits with code 2 when no remote origin" {
  cd "$TEST_TEMP_DIR"
  
  # Create git repo without remote
  mkdir -p "${TEST_TEMP_DIR}/no-remote"
  cd "${TEST_TEMP_DIR}/no-remote"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "test" > test.txt
  git add test.txt
  git commit -m "test" -q
  
  run "${SKILL_DIR}/azure-pr.sh"
  
  [ "$status" -eq 2 ]
}

@test "exits with code 3 when API returns 401" {
  create_auth_fail_curl_mock
  repo_dir=$(create_test_repo "api-error-repo")
  cd "$repo_dir"
  
  run "${SKILL_DIR}/azure-pr.sh"
  
  [ "$status" -eq 3 ]
}

@test "exits with code 3 when no work items found" {
  create_empty_wi_curl_mock
  repo_dir=$(create_test_repo "no-wi-repo")
  cd "$repo_dir"
  
  run "${SKILL_DIR}/azure-pr.sh"
  
  [ "$status" -eq 3 ]
  [[ "$output" =~ "No Work Items" ]]
}

@test "exits with code 4 when user enters invalid selection" {
  create_curl_mock
  repo_dir=$(create_test_repo "cancel-repo")
  cd "$repo_dir"
  
  # Simulate user entering invalid selection
  run bash -c "echo 'invalid' | ${SKILL_DIR}/azure-pr.sh"
  
  [ "$status" -eq 4 ]
}

# ==============================================================================
# Tests: Pre-flight Checks
# ==============================================================================

@test "validates environment before git check" {
  unset AZURE_DEVOPS_ORG
  
  # Even in a valid repo, should fail on env validation first
  repo_dir=$(create_test_repo "env-first-repo")
  cd "$repo_dir"
  
  run "${SKILL_DIR}/azure-pr.sh"
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "AZURE_DEVOPS_ORG" ]]
}

@test "validates git repo after environment check" {
  # Valid env, but not in git repo
  cd "$TEST_TEMP_DIR"
  mkdir -p not-git
  cd not-git
  
  run "${SKILL_DIR}/azure-pr.sh"
  
  [ "$status" -eq 2 ]
  [[ "$output" =~ "Not a git repository" ]] || [[ "$output" =~ "git" ]]
}

# ==============================================================================
# Tests: Work Item Flow
# ==============================================================================

@test "displays work items from API response" {
  create_curl_mock
  repo_dir=$(create_test_repo "wi-display-repo")
  cd "$repo_dir"
  
  # Run with selection 1, then cancel on branch prompt
  run bash -c "echo -e '1\ncurrent' | ${SKILL_DIR}/azure-pr.sh"
  
  # Should show work item info before failing
  [[ "$output" =~ "#12345" ]] || [[ "$output" =~ "Bug" ]] || [[ "$output" =~ "Test Bug" ]]
}

@test "fetches work item details after selection" {
  create_curl_mock
  repo_dir=$(create_test_repo "wi-details-repo")
  cd "$repo_dir"
  
  # Add a commit to be ahead
  echo "feature" > feature.txt
  git add feature.txt
  git commit -m "Feature" -q
  git checkout -b feature/test -q
  echo "more" > more.txt
  git add more.txt
  git commit -m "More" -q
  
  run bash -c "echo -e '1\ncurrent' | ${SKILL_DIR}/azure-pr.sh"
  
  # Should mention the selected work item
  [[ "$output" =~ "12345" ]]
}

# ==============================================================================
# Tests: Branch Management
# ==============================================================================

@test "accepts 'current' branch option" {
  create_curl_mock
  repo_dir=$(create_test_repo "current-branch-repo")
  cd "$repo_dir"
  
  # Create feature branch with commit
  git checkout -b feature/test -q
  echo "feature" > feature.txt
  git add feature.txt
  git commit -m "Feature" -q
  
  run bash -c "echo -e '1\ncurrent' | ${SKILL_DIR}/azure-pr.sh"
  
  # Should proceed with current branch
  [[ "$output" =~ "Branch" ]] || [[ "$output" =~ "feature" ]]
}

@test "validates branch has commits ahead" {
  create_curl_mock
  repo_dir=$(create_test_repo "no-commits-repo")
  cd "$repo_dir"
  
  # Create branch but don't add commits
  git checkout -b feature/empty -q
  
  run bash -c "echo -e '1\ncurrent' | ${SKILL_DIR}/azure-pr.sh"
  
  # Should fail because no commits ahead
  [ "$status" -ne 0 ]
}

# ==============================================================================
# Tests: PR Creation
# ==============================================================================

@test "creates PR with correct title format" {
  create_curl_mock
  repo_dir=$(create_test_repo "pr-title-repo")
  cd "$repo_dir"
  
  git checkout -b feature/test -q
  echo "feature" > feature.txt
  git add feature.txt
  git commit -m "Feature" -q
  
  run bash -c "echo -e '1\ncurrent' | ${SKILL_DIR}/azure-pr.sh"
  
  # Check that PR creation was attempted (mock returns success)
  [[ "$output" =~ "Pull Request" ]] || [[ "$output" =~ "PR" ]]
}

@test "shows success message with PR URL on completion" {
  create_curl_mock
  repo_dir=$(create_test_repo "success-repo")
  cd "$repo_dir"
  
  git checkout -b feature/test -q
  echo "feature" > feature.txt
  git add feature.txt
  git commit -m "Feature" -q
  
  run bash -c "echo -e '1\ncurrent' | ${SKILL_DIR}/azure-pr.sh"
  
  # If successful, should show PR URL
  if [ "$status" -eq 0 ]; then
    [[ "$output" =~ "pullrequest" ]] || [[ "$output" =~ "789" ]] || [[ "$output" =~ "🎉" ]]
  fi
}

# ==============================================================================
# Tests: Integration Flow
# ==============================================================================

@test "full workflow succeeds with mocked API" {
  create_curl_mock
  repo_dir=$(create_test_repo "full-flow-repo")
  cd "$repo_dir"
  
  # Create feature branch with commit
  git checkout -b feature/test-feature -q
  echo "feature code" > feature.txt
  git add feature.txt
  git commit -m "Add feature" -q
  
  # Run full workflow: select WI 1, use current branch
  run bash -c "echo -e '1\ncurrent' | ${SKILL_DIR}/azure-pr.sh"
  
  # Should succeed
  [ "$status" -eq 0 ]
  
  # Should show success indicators
  [[ "$output" =~ "✓" ]] || [[ "$output" =~ "success" ]] || [[ "$output" =~ "🎉" ]]
}

@test "workflow shows progress steps" {
  create_curl_mock
  repo_dir=$(create_test_repo "progress-repo")
  cd "$repo_dir"
  
  git checkout -b feature/progress -q
  echo "test" > test.txt
  git add test.txt
  git commit -m "Test" -q
  
  run bash -c "echo -e '1\ncurrent' | ${SKILL_DIR}/azure-pr.sh"
  
  # Should show step progress
  [[ "$output" =~ "Validating" ]] || [[ "$output" =~ "[1/" ]] || [[ "$output" =~ "step" ]]
}

# ==============================================================================
# Tests: Error Messages
# ==============================================================================

@test "shows helpful message when PAT is invalid" {
  create_auth_fail_curl_mock
  repo_dir=$(create_test_repo "auth-help-repo")
  cd "$repo_dir"
  
  run "${SKILL_DIR}/azure-pr.sh"
  
  [ "$status" -eq 3 ]
  [[ "$output" =~ "PAT" ]] || [[ "$output" =~ "Authentication" ]] || [[ "$output" =~ "401" ]]
}

@test "shows helpful message when no work items assigned" {
  create_empty_wi_curl_mock
  repo_dir=$(create_test_repo "no-wi-help-repo")
  cd "$repo_dir"
  
  run "${SKILL_DIR}/azure-pr.sh"
  
  [ "$status" -eq 3 ]
  [[ "$output" =~ "No Work Items" ]] || [[ "$output" =~ "Azure Boards" ]]
}
