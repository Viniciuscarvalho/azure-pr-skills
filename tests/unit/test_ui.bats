#!/usr/bin/env bats
# File: ~/.claude/skills/azure-devops-pr/tests/unit/test_ui.bats
# Unit tests for the UI components module
# Run with: bats tests/unit/test_ui.bats

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
  export AZURE_DEVOPS_PAT="test-pat-12345678901234567890"
  export AZURE_DEVOPS_DEBUG="false"
  
  # Create temp directory
  TEST_TEMP_DIR=$(mktemp -d)
  
  # Load modules
  source "${SKILL_DIR}/lib/config.sh"
  source "${SKILL_DIR}/lib/ui.sh"
}

teardown() {
  # Clean up temp directory
  if [[ -d "$TEST_TEMP_DIR" ]]; then
    rm -rf "$TEST_TEMP_DIR"
  fi
}

# ==============================================================================
# Test Data Helpers
# ==============================================================================

# Create sample Work Items JSON (batch response format)
create_work_items_json() {
  cat <<'EOF'
{
  "count": 3,
  "value": [
    {
      "id": 12345,
      "fields": {
        "System.WorkItemType": "Bug",
        "System.Title": "Fix authentication timeout",
        "System.State": "Active"
      }
    },
    {
      "id": 12346,
      "fields": {
        "System.WorkItemType": "Feature",
        "System.Title": "Add dark mode support",
        "System.State": "New"
      }
    },
    {
      "id": 12347,
      "fields": {
        "System.WorkItemType": "Task",
        "System.Title": "Update API documentation",
        "System.State": "In Progress"
      }
    }
  ]
}
EOF
}

# Create single Work Item JSON
create_single_work_item_json() {
  cat <<'EOF'
{
  "id": 12345,
  "fields": {
    "System.WorkItemType": "Bug",
    "System.Title": "Fix authentication timeout",
    "System.State": "Active",
    "System.Description": "Login times out after 30 seconds",
    "Microsoft.VSTS.Common.AcceptanceCriteria": "User can login within 5s"
  }
}
EOF
}

# Create empty Work Items JSON
create_empty_work_items_json() {
  echo '{"count": 0, "value": []}'
}

# ==============================================================================
# Tests: Formatting Helpers
# ==============================================================================

@test "truncate_string truncates long strings" {
  result=$(truncate_string "This is a very long string that should be truncated" 20)
  
  [ ${#result} -eq 20 ]
  [[ "$result" =~ "..." ]]
}

@test "truncate_string keeps short strings unchanged" {
  result=$(truncate_string "Short" 20)
  
  [ "$result" = "Short" ]
}

@test "truncate_string uses default max length" {
  result=$(truncate_string "This is a test string that is not too long")
  
  # Should not be truncated with default length of 60
  [[ ! "$result" =~ "..." ]]
}

@test "format_work_item_type formats correctly" {
  result=$(format_work_item_type "Bug")
  
  [ "$result" = "[Bug]" ]
}

# ==============================================================================
# Tests: Logging Functions
# ==============================================================================

@test "info outputs message with emoji" {
  run info "Test message"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ℹ️" ]] || [[ "$output" =~ "Test message" ]]
}

@test "warn outputs message to stderr" {
  run warn "Warning message"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "⚠️" ]] || [[ "$output" =~ "Warning" ]]
}

@test "error outputs message to stderr" {
  run error "Error message"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "❌" ]] || [[ "$output" =~ "Error" ]]
}

@test "success outputs message with checkmark" {
  run success "Success message"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "✓" ]]
}

# ==============================================================================
# Tests: Loading Indicators
# ==============================================================================

@test "show_loading displays loading message" {
  run show_loading "Loading data"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "⏳" ]] || [[ "$output" =~ "Loading" ]]
}

@test "show_loading_done displays completion" {
  run show_loading_done "Complete"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "✓" ]]
}

@test "show_step displays step progress" {
  run show_step 2 5 "Processing"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "[2/5]" ]]
  [[ "$output" =~ "Processing" ]]
}

@test "show_in_progress displays progress" {
  run show_in_progress "Loading Work Items"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "⏳" ]]
}

@test "show_completed displays completion" {
  run show_completed "Work Items loaded"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "✓" ]]
}

@test "show_failed displays failure" {
  run show_failed "Connection failed"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "✗" ]]
}

# ==============================================================================
# Tests: Work Item Selection
# ==============================================================================

@test "prompt_work_item_selection displays work items" {
  local wi_json=$(create_work_items_json)
  
  # Simulate user input: select option 1
  run bash -c "source ${SKILL_DIR}/lib/config.sh && source ${SKILL_DIR}/lib/ui.sh && echo '1' | prompt_work_item_selection '$wi_json'"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "#12345" ]]
  [[ "$output" =~ "[Bug]" ]]
  [[ "$output" =~ "Active" ]]
}

@test "prompt_work_item_selection returns correct ID for selection 1" {
  local wi_json=$(create_work_items_json)
  
  result=$(echo "1" | prompt_work_item_selection "$wi_json" 2>/dev/null)
  
  [ "$result" = "12345" ]
}

@test "prompt_work_item_selection returns correct ID for selection 2" {
  local wi_json=$(create_work_items_json)
  
  result=$(echo "2" | prompt_work_item_selection "$wi_json" 2>/dev/null)
  
  [ "$result" = "12346" ]
}

@test "prompt_work_item_selection returns correct ID for selection 3" {
  local wi_json=$(create_work_items_json)
  
  result=$(echo "3" | prompt_work_item_selection "$wi_json" 2>/dev/null)
  
  [ "$result" = "12347" ]
}

@test "prompt_work_item_selection rejects non-numeric input" {
  local wi_json=$(create_work_items_json)
  
  run bash -c "source ${SKILL_DIR}/lib/config.sh && source ${SKILL_DIR}/lib/ui.sh && echo 'abc' | prompt_work_item_selection '$wi_json'"
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Invalid" ]] || [[ "$output" =~ "not a number" ]]
}

@test "prompt_work_item_selection rejects out of range selection" {
  local wi_json=$(create_work_items_json)
  
  run bash -c "source ${SKILL_DIR}/lib/config.sh && source ${SKILL_DIR}/lib/ui.sh && echo '99' | prompt_work_item_selection '$wi_json'"
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "out of range" ]] || [[ "$output" =~ "Invalid" ]]
}

@test "prompt_work_item_selection rejects zero" {
  local wi_json=$(create_work_items_json)
  
  run bash -c "source ${SKILL_DIR}/lib/config.sh && source ${SKILL_DIR}/lib/ui.sh && echo '0' | prompt_work_item_selection '$wi_json'"
  
  [ "$status" -eq 1 ]
}

@test "prompt_work_item_selection rejects negative numbers" {
  local wi_json=$(create_work_items_json)
  
  run bash -c "source ${SKILL_DIR}/lib/config.sh && source ${SKILL_DIR}/lib/ui.sh && echo '-1' | prompt_work_item_selection '$wi_json'"
  
  [ "$status" -eq 1 ]
}

@test "prompt_work_item_selection handles empty work items" {
  local wi_json=$(create_empty_work_items_json)
  
  run bash -c "source ${SKILL_DIR}/lib/config.sh && source ${SKILL_DIR}/lib/ui.sh && prompt_work_item_selection '$wi_json'"
  
  [ "$status" -eq 2 ]
  [[ "$output" =~ "No Work Items" ]]
}

@test "prompt_work_item_selection rejects empty input" {
  local wi_json=$(create_work_items_json)
  
  run bash -c "source ${SKILL_DIR}/lib/config.sh && source ${SKILL_DIR}/lib/ui.sh && echo '' | prompt_work_item_selection '$wi_json'"
  
  [ "$status" -eq 1 ]
}

# ==============================================================================
# Tests: Work Item Display
# ==============================================================================

@test "display_work_item_summary shows work item details" {
  local wi_json=$(create_single_work_item_json)
  
  run display_work_item_summary "$wi_json"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "#12345" ]]
  [[ "$output" =~ "Bug" ]]
  [[ "$output" =~ "Fix authentication timeout" ]]
}

# ==============================================================================
# Tests: Success Display
# ==============================================================================

@test "display_success shows PR URL" {
  # Create a minimal git repo for get_repository_name
  cd "$TEST_TEMP_DIR"
  git init -q
  git remote add origin "https://dev.azure.com/org/project/_git/my-repo"
  
  run display_success "789" "12345"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "pullrequest/789" ]]
}

@test "display_success shows checkmarks" {
  cd "$TEST_TEMP_DIR"
  git init -q
  git remote add origin "https://dev.azure.com/org/project/_git/repo"
  
  run display_success "123" "456"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "✓" ]]
  [[ "$output" =~ "Work Item" ]]
  [[ "$output" =~ "PR created" ]]
}

@test "display_success includes Azure DevOps URL format" {
  cd "$TEST_TEMP_DIR"
  git init -q
  git remote add origin "https://dev.azure.com/org/project/_git/my-repo"
  
  run display_success "100" "200"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "dev.azure.com" ]]
  [[ "$output" =~ "test-org" ]]
  [[ "$output" =~ "test-project" ]]
}

@test "display_success shows celebration emoji" {
  cd "$TEST_TEMP_DIR"
  git init -q
  git remote add origin "https://dev.azure.com/org/project/_git/repo"
  
  run display_success "1" "2"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "🎉" ]]
}

@test "display_success outputs URL to stdout" {
  cd "$TEST_TEMP_DIR"
  git init -q
  git remote add origin "https://dev.azure.com/org/project/_git/repo"
  
  # Capture only stdout
  result=$(display_success "555" "666" 2>/dev/null)
  
  [[ "$result" =~ "pullrequest/555" ]]
}

# ==============================================================================
# Tests: Error Display
# ==============================================================================

@test "display_error shows auth suggestions for auth errors" {
  run display_error "auth" "Authentication failed"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "PAT" ]]
  [[ "$output" =~ "expired" ]] || [[ "$output" =~ "scopes" ]]
}

@test "display_error shows network suggestions for network errors" {
  run display_error "network" "Connection failed"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "internet" ]] || [[ "$output" =~ "connection" ]]
}

@test "display_error shows git suggestions for git errors" {
  run display_error "git" "Not a git repository"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "repository" ]] || [[ "$output" =~ "origin" ]]
}

# ==============================================================================
# Tests: Progress Display
# ==============================================================================

@test "display_progress shows multiple steps" {
  run display_progress "Step 1 done" "Step 2 done" "Step 3 done"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Step 1" ]]
  [[ "$output" =~ "Step 2" ]]
  [[ "$output" =~ "Step 3" ]]
}

# ==============================================================================
# Tests: Confirmation Prompt
# ==============================================================================

@test "confirm returns 0 for yes" {
  run bash -c "source ${SKILL_DIR}/lib/ui.sh && echo 'y' | confirm 'Continue?'"
  
  [ "$status" -eq 0 ]
}

@test "confirm returns 0 for YES" {
  run bash -c "source ${SKILL_DIR}/lib/ui.sh && echo 'YES' | confirm 'Continue?'"
  
  [ "$status" -eq 0 ]
}

@test "confirm returns 1 for no" {
  run bash -c "source ${SKILL_DIR}/lib/ui.sh && echo 'n' | confirm 'Continue?'"
  
  [ "$status" -eq 1 ]
}

@test "confirm uses default when empty" {
  # Default is 'n'
  run bash -c "source ${SKILL_DIR}/lib/ui.sh && echo '' | confirm 'Continue?' 'n'"
  
  [ "$status" -eq 1 ]
}

@test "confirm accepts y as default" {
  run bash -c "source ${SKILL_DIR}/lib/ui.sh && echo '' | confirm 'Continue?' 'y'"
  
  [ "$status" -eq 0 ]
}

# ==============================================================================
# Tests: Utility Functions
# ==============================================================================

@test "print_indicator info type works" {
  run print_indicator "info" "Test info"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ℹ️" ]] || [[ "$output" =~ "Test info" ]]
}

@test "print_indicator success type works" {
  run print_indicator "success" "Test success"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "✓" ]]
}

@test "print_indicator error type works" {
  run print_indicator "error" "Test error"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "❌" ]] || [[ "$output" =~ "Test error" ]]
}
