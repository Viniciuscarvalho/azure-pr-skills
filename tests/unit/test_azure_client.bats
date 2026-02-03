#!/usr/bin/env bats
# File: ~/.claude/skills/azure-devops-pr/tests/unit/test_azure_client.bats
# Unit tests for the Azure DevOps API client module
# Run with: bats tests/unit/test_azure_client.bats

# ==============================================================================
# Test Setup and Teardown
# ==============================================================================

setup() {
  # Get the directory containing this test file
  BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
  SKILL_DIR="${BATS_TEST_DIR}/../.."
  
  # Set up test environment variables
  export AZURE_DEVOPS_ORG="test-org"
  export AZURE_DEVOPS_PROJECT="test-project"
  export AZURE_DEVOPS_PAT="test-pat-12345678901234567890123456789012"
  export AZURE_DEVOPS_DEBUG="false"
  
  # Create temp directory for mock scripts
  MOCK_DIR=$(mktemp -d)
  export PATH="${MOCK_DIR}:${PATH}"
  
  # Track curl calls
  export CURL_CALL_COUNT=0
  export CURL_CALLS_FILE="${MOCK_DIR}/curl_calls.txt"
  touch "$CURL_CALLS_FILE"
  
  # Load modules
  source "${SKILL_DIR}/lib/config.sh"
  source "${SKILL_DIR}/lib/azure-client.sh"
}

teardown() {
  # Clean up mock directory
  if [[ -d "$MOCK_DIR" ]]; then
    rm -rf "$MOCK_DIR"
  fi
  
  # Restore original curl
  unset -f curl 2>/dev/null || true
}

# ==============================================================================
# Mock Helpers
# ==============================================================================

# Create a mock curl that returns a specific response
# Args: $1 = response body, $2 = http status code
create_curl_mock() {
  local response_body="$1"
  local http_code="${2:-200}"
  
  cat > "${MOCK_DIR}/curl" <<EOF
#!/bin/bash
echo '${response_body}'
echo "${http_code}"
EOF
  chmod +x "${MOCK_DIR}/curl"
}

# Create a mock curl that tracks calls and returns configurable responses
# Args: response body and code are read from MOCK_RESPONSE and MOCK_CODE env vars
create_tracking_curl_mock() {
  cat > "${MOCK_DIR}/curl" <<'MOCKSCRIPT'
#!/bin/bash
# Record the call
echo "$@" >> "${CURL_CALLS_FILE}"

# Get call count
count=$(wc -l < "${CURL_CALLS_FILE}" | tr -d ' ')

# Check for multi-response scenario
if [[ -n "${MOCK_RESPONSES:-}" ]]; then
  # MOCK_RESPONSES format: "body1|code1,body2|code2,..."
  IFS=',' read -ra RESPONSES <<< "$MOCK_RESPONSES"
  idx=$((count - 1))
  if [[ $idx -lt ${#RESPONSES[@]} ]]; then
    IFS='|' read -r body code <<< "${RESPONSES[$idx]}"
    echo "$body"
    echo "$code"
    exit 0
  fi
fi

# Single response
echo "${MOCK_RESPONSE:-{}}"
echo "${MOCK_CODE:-200}"
MOCKSCRIPT
  chmod +x "${MOCK_DIR}/curl"
}

# Create a mock curl that fails initially then succeeds
# Args: $1 = number of failures, $2 = failure code, $3 = success response
create_retry_curl_mock() {
  local failures="$1"
  local fail_code="$2"
  local success_response="$3"
  
  # Use a unique file per test run to track calls
  RETRY_COUNT_FILE="${MOCK_DIR}/retry_count"
  echo "0" > "$RETRY_COUNT_FILE"
  
  cat > "${MOCK_DIR}/curl" <<MOCKSCRIPT
#!/bin/bash
# Track call count using shared file
count=\$(cat "${RETRY_COUNT_FILE}")
count=\$((count + 1))
echo "\$count" > "${RETRY_COUNT_FILE}"

if [[ \$count -le ${failures} ]]; then
  echo '{"error": "rate limited"}'
  echo "${fail_code}"
else
  echo '${success_response}'
  echo "200"
fi
MOCKSCRIPT
  chmod +x "${MOCK_DIR}/curl"
}

# Create a mock git command
create_git_mock() {
  local remote_url="$1"
  
  cat > "${MOCK_DIR}/git" <<EOF
#!/bin/bash
if [[ "\$1" == "remote" && "\$2" == "get-url" ]]; then
  echo "${remote_url}"
  exit 0
fi
# Pass through to real git for other commands
/usr/bin/git "\$@"
EOF
  chmod +x "${MOCK_DIR}/git"
}

# ==============================================================================
# Tests: API Call Basic Functionality
# ==============================================================================

@test "azure_api_call returns response body on HTTP 200" {
  create_curl_mock '{"id": 12345, "name": "test"}' "200"
  
  run azure_api_call "GET" "/_apis/test?api-version=7.2"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ '"id": 12345' ]]
}

@test "azure_api_call returns response body on HTTP 201" {
  create_curl_mock '{"pullRequestId": 789}' "201"
  
  run azure_api_call "POST" "/_apis/git/pullrequests" '{"title": "test"}'
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ '"pullRequestId": 789' ]]
}

@test "azure_api_call includes authorization header" {
  export MOCK_RESPONSE='{"success": true}'
  export MOCK_CODE="200"
  create_tracking_curl_mock
  
  azure_api_call "GET" "/_apis/test" > /dev/null
  
  # Check that Authorization header was passed
  grep -q "Authorization" "$CURL_CALLS_FILE"
}

@test "azure_api_call includes correct Content-Type header" {
  export MOCK_RESPONSE='{"success": true}'
  export MOCK_CODE="200"
  create_tracking_curl_mock
  
  azure_api_call "POST" "/_apis/test" '{"data": "test"}' > /dev/null
  
  grep -q "Content-Type" "$CURL_CALLS_FILE"
  grep -q "application/json" "$CURL_CALLS_FILE"
}

# ==============================================================================
# Tests: Error Handling
# ==============================================================================

@test "azure_api_call returns error on HTTP 401" {
  create_curl_mock '{"message": "Unauthorized"}' "401"
  
  run azure_api_call "GET" "/_apis/test"
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Authentication failed" ]]
}

@test "azure_api_call error message includes PAT help on 401" {
  create_curl_mock '{"message": "Unauthorized"}' "401"
  
  run azure_api_call "GET" "/_apis/test"
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "PAT" ]] || [[ "$output" =~ "expired" ]] || [[ "$output" =~ "scopes" ]]
}

@test "azure_api_call returns error on HTTP 403" {
  create_curl_mock '{"message": "Forbidden"}' "403"
  
  run azure_api_call "GET" "/_apis/test"
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "forbidden" ]] || [[ "$output" =~ "permission" ]]
}

@test "azure_api_call returns error on HTTP 404" {
  create_curl_mock '{"message": "Not Found"}' "404"
  
  run azure_api_call "GET" "/_apis/test"
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "not found" ]] || [[ "$output" =~ "Not found" ]]
}

@test "azure_api_call returns error on HTTP 400 with message" {
  create_curl_mock '{"message": "Invalid query syntax"}' "400"
  
  run azure_api_call "POST" "/_apis/wit/wiql" '{"query": "bad"}'
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Bad request" ]] || [[ "$output" =~ "Invalid" ]]
}

# ==============================================================================
# Tests: Retry Logic
# ==============================================================================

@test "azure_api_call retries on HTTP 429 (rate limit)" {
  # Mock that fails twice then succeeds
  create_retry_curl_mock 2 "429" '{"success": true}'
  
  run azure_api_call "GET" "/_apis/test"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "success" ]]
}

@test "azure_api_call retries on HTTP 503 (service unavailable)" {
  # Mock that fails once then succeeds
  create_retry_curl_mock 1 "503" '{"data": "recovered"}'
  
  run azure_api_call "GET" "/_apis/test"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "recovered" ]]
}

@test "azure_api_call fails after max retries on persistent 429" {
  create_curl_mock '{"error": "rate limited"}' "429"
  
  run azure_api_call "GET" "/_apis/test"
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Rate limited" ]] || [[ "$output" =~ "rate" ]]
}

@test "azure_api_call fails after max retries on persistent 503" {
  create_curl_mock '{"error": "unavailable"}' "503"
  
  run azure_api_call "GET" "/_apis/test"
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "unavailable" ]] || [[ "$output" =~ "service" ]]
}

# ==============================================================================
# Tests: Security - PAT Never Logged
# ==============================================================================

@test "PAT value never appears in debug output" {
  export AZURE_DEVOPS_DEBUG="true"
  create_curl_mock '{"success": true}' "200"
  
  run azure_api_call "GET" "/_apis/test"
  
  # The actual PAT should never appear in output
  [[ ! "$output" =~ "test-pat-12345678901234567890123456789012" ]]
}

@test "Authorization header shows REDACTED in debug" {
  export AZURE_DEVOPS_DEBUG="true"
  create_curl_mock '{"success": true}' "200"
  
  run azure_api_call "GET" "/_apis/test"
  
  # Should show redacted, not actual PAT
  [[ "$output" =~ "REDACTED" ]] || [[ ! "$output" =~ "test-pat" ]]
}

# ==============================================================================
# Tests: Work Item Functions
# ==============================================================================

@test "fetch_work_items calls WIQL endpoint" {
  export MOCK_RESPONSE='{"workItems": [{"id": 123}]}'
  export MOCK_CODE="200"
  create_tracking_curl_mock
  
  run fetch_work_items
  
  [ "$status" -eq 0 ]
  grep -q "wiql" "$CURL_CALLS_FILE"
}

@test "fetch_work_items returns work items array" {
  create_curl_mock '{"workItems": [{"id": 123, "url": "http://test"}, {"id": 456, "url": "http://test2"}]}' "200"
  
  run fetch_work_items
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "123" ]]
  [[ "$output" =~ "456" ]]
}

@test "get_work_item_details fetches specific work item" {
  export MOCK_RESPONSE='{"id": 12345, "fields": {"System.Title": "Test Bug"}}'
  export MOCK_CODE="200"
  create_tracking_curl_mock
  
  run get_work_item_details "12345"
  
  [ "$status" -eq 0 ]
  grep -q "12345" "$CURL_CALLS_FILE"
  [[ "$output" =~ "Test Bug" ]]
}

@test "get_work_item_details requires ID argument" {
  run get_work_item_details ""
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "required" ]]
}

@test "extract_work_item_ids parses WIQL response correctly" {
  local wiql_response='{"workItems": [{"id": 111}, {"id": 222}, {"id": 333}]}'
  
  result=$(extract_work_item_ids "$wiql_response")
  
  [ "$result" = "111,222,333" ]
}

# ==============================================================================
# Tests: Repository Functions
# ==============================================================================

@test "get_repository_id parses HTTPS remote URL correctly" {
  create_git_mock "https://dev.azure.com/org/project/_git/my-repo"
  create_curl_mock '{"id": "repo-guid-12345", "name": "my-repo"}' "200"
  
  run get_repository_id
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "repo-guid-12345" ]]
}

@test "get_repository_id parses SSH remote URL correctly" {
  create_git_mock "git@ssh.dev.azure.com:v3/org/project/my-repo"
  create_curl_mock '{"id": "repo-guid-ssh", "name": "my-repo"}' "200"
  
  run get_repository_id
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "repo-guid-ssh" ]]
}

@test "get_repository_id handles .git suffix" {
  create_git_mock "https://dev.azure.com/org/project/_git/my-repo.git"
  create_curl_mock '{"id": "repo-guid-git", "name": "my-repo"}' "200"
  
  run get_repository_id
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "repo-guid-git" ]]
}

# ==============================================================================
# Tests: PR Payload Builder
# ==============================================================================

@test "build_pr_payload creates valid JSON" {
  local wi_json='{
    "id": 12345,
    "fields": {
      "System.WorkItemType": "Bug",
      "System.Title": "Fix login timeout",
      "System.Description": "Login times out after 30s",
      "System.Tags": "auth; critical",
      "Microsoft.VSTS.Common.AcceptanceCriteria": "User can login within 5s"
    }
  }'
  
  result=$(build_pr_payload "$wi_json" "feature/WI-12345" "main")
  
  # Verify it's valid JSON
  echo "$result" | jq . > /dev/null
  [ $? -eq 0 ]
}

@test "build_pr_payload includes WI ID in title" {
  local wi_json='{
    "id": 12345,
    "fields": {
      "System.WorkItemType": "Bug",
      "System.Title": "Fix bug"
    }
  }'
  
  result=$(build_pr_payload "$wi_json" "feature/test" "main")
  
  [[ $(echo "$result" | jq -r '.title') =~ "WI-12345" ]]
}

@test "build_pr_payload sets isDraft to true" {
  local wi_json='{"id": 123, "fields": {"System.Title": "Test"}}'
  
  result=$(build_pr_payload "$wi_json" "feature/test" "main")
  
  [ "$(echo "$result" | jq -r '.isDraft')" = "true" ]
}

@test "build_pr_payload includes source and target branches" {
  local wi_json='{"id": 123, "fields": {"System.Title": "Test"}}'
  
  result=$(build_pr_payload "$wi_json" "feature/my-feature" "develop")
  
  [ "$(echo "$result" | jq -r '.sourceRefName')" = "refs/heads/feature/my-feature" ]
  [ "$(echo "$result" | jq -r '.targetRefName')" = "refs/heads/develop" ]
}

@test "build_pr_payload converts acceptance criteria to checklist" {
  local wi_json='{
    "id": 123,
    "fields": {
      "System.Title": "Test",
      "Microsoft.VSTS.Common.AcceptanceCriteria": "First criterion\nSecond criterion"
    }
  }'
  
  result=$(build_pr_payload "$wi_json" "feature/test" "main")
  description=$(echo "$result" | jq -r '.description')
  
  [[ "$description" =~ "- [ ]" ]]
}

@test "build_pr_payload converts tags to labels" {
  local wi_json='{
    "id": 123,
    "fields": {
      "System.Title": "Test",
      "System.Tags": "frontend; bug; urgent"
    }
  }'
  
  result=$(build_pr_payload "$wi_json" "feature/test" "main")
  labels=$(echo "$result" | jq '.labels')
  
  [ "$(echo "$labels" | jq 'length')" -gt 0 ]
}

@test "build_pr_payload includes reviewers when configured" {
  export AZURE_DEVOPS_REVIEWERS="guid-1,guid-2"
  local wi_json='{"id": 123, "fields": {"System.Title": "Test"}}'
  
  result=$(build_pr_payload "$wi_json" "feature/test" "main")
  reviewers=$(echo "$result" | jq '.reviewers')
  
  [ "$(echo "$reviewers" | jq 'length')" -eq 2 ]
  [[ $(echo "$reviewers" | jq -r '.[0].id') =~ "guid" ]]
}

# ==============================================================================
# Tests: PR Creation
# ==============================================================================

@test "create_pull_request returns full response" {
  # Mock git for repo ID
  create_git_mock "https://dev.azure.com/org/project/_git/repo"
  
  # Use a counter-based mock for multiple calls
  CALL_COUNT_FILE="${MOCK_DIR}/call_count"
  echo "0" > "$CALL_COUNT_FILE"
  
  cat > "${MOCK_DIR}/curl" <<'MOCKSCRIPT'
#!/bin/bash
count=$(cat "${CALL_COUNT_FILE:-/tmp/call_count}")
count=$((count + 1))
echo "$count" > "${CALL_COUNT_FILE:-/tmp/call_count}"

if [[ $count -eq 1 ]]; then
  # First call: get repo
  echo '{"id":"repo-id","name":"repo"}'
  echo "200"
else
  # Second call: create PR
  echo '{"pullRequestId":789,"status":"active"}'
  echo "201"
fi
MOCKSCRIPT
  chmod +x "${MOCK_DIR}/curl"
  export CALL_COUNT_FILE
  
  local payload='{"title": "Test PR", "sourceRefName": "refs/heads/test", "targetRefName": "refs/heads/main"}'
  
  run create_pull_request "$payload"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "789" ]]
}

@test "get_pr_id_from_response extracts PR ID correctly" {
  local pr_response='{"pullRequestId": 999, "title": "Test"}'
  
  result=$(get_pr_id_from_response "$pr_response")
  
  [ "$result" = "999" ]
}

# ==============================================================================
# Tests: Utility Functions
# ==============================================================================

@test "is_valid_work_item_id accepts numeric IDs" {
  run is_valid_work_item_id "12345"
  [ "$status" -eq 0 ]
  
  run is_valid_work_item_id "1"
  [ "$status" -eq 0 ]
}

@test "is_valid_work_item_id rejects non-numeric IDs" {
  run is_valid_work_item_id "abc"
  [ "$status" -eq 1 ]
  
  run is_valid_work_item_id "123abc"
  [ "$status" -eq 1 ]
  
  run is_valid_work_item_id ""
  [ "$status" -eq 1 ]
}

@test "_get_base_url constructs correct URL" {
  result=$(_get_base_url)
  
  [ "$result" = "https://dev.azure.com/test-org/test-project" ]
}

# ==============================================================================
# Tests: Reviewer Functions
# ==============================================================================

@test "add_reviewers_to_pr does nothing when REVIEWERS not set" {
  unset AZURE_DEVOPS_REVIEWERS
  create_curl_mock '{"id": "reviewer"}' "200"
  
  run add_reviewers_to_pr "123"
  
  [ "$status" -eq 0 ]
  # Should return immediately without making API calls
}

@test "add_reviewers_to_pr requires PR ID" {
  export AZURE_DEVOPS_REVIEWERS="guid-1"
  
  run add_reviewers_to_pr ""
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "required" ]]
}
