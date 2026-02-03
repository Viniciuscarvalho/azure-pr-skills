#!/usr/bin/env bats
# File: ~/.claude/skills/azure-devops-pr/tests/unit/test_config.bats
# Unit tests for the configuration validation module
# Run with: bats tests/unit/test_config.bats

# ==============================================================================
# Test Setup and Teardown
# ==============================================================================

setup() {
  # Get the directory containing this test file
  BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
  
  # Load the module under test
  source "${BATS_TEST_DIR}/../../lib/config.sh"
  
  # Save original environment variables
  ORIGINAL_ORG="${AZURE_DEVOPS_ORG:-}"
  ORIGINAL_PROJECT="${AZURE_DEVOPS_PROJECT:-}"
  ORIGINAL_PAT="${AZURE_DEVOPS_PAT:-}"
  ORIGINAL_REVIEWERS="${AZURE_DEVOPS_REVIEWERS:-}"
  ORIGINAL_TARGET_BRANCH="${AZURE_DEVOPS_TARGET_BRANCH:-}"
  ORIGINAL_DEBUG="${AZURE_DEVOPS_DEBUG:-}"
}

teardown() {
  # Restore original environment variables
  export AZURE_DEVOPS_ORG="$ORIGINAL_ORG"
  export AZURE_DEVOPS_PROJECT="$ORIGINAL_PROJECT"
  export AZURE_DEVOPS_PAT="$ORIGINAL_PAT"
  export AZURE_DEVOPS_REVIEWERS="$ORIGINAL_REVIEWERS"
  export AZURE_DEVOPS_TARGET_BRANCH="$ORIGINAL_TARGET_BRANCH"
  export AZURE_DEVOPS_DEBUG="$ORIGINAL_DEBUG"
}

# ==============================================================================
# Helper Functions
# ==============================================================================

# Set up valid configuration for tests
set_valid_config() {
  export AZURE_DEVOPS_ORG="test-org"
  export AZURE_DEVOPS_PROJECT="test-project"
  # A valid PAT is typically 52 characters - using a dummy 52-char string
  export AZURE_DEVOPS_PAT="abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOP"
}

# Clear all Azure DevOps environment variables
clear_all_config() {
  unset AZURE_DEVOPS_ORG
  unset AZURE_DEVOPS_PROJECT
  unset AZURE_DEVOPS_PAT
  unset AZURE_DEVOPS_REVIEWERS
  unset AZURE_DEVOPS_TARGET_BRANCH
  unset AZURE_DEVOPS_DEBUG
}

# ==============================================================================
# Tests: Valid Configuration
# ==============================================================================

@test "accepts valid configuration with all required variables" {
  set_valid_config
  
  run validate_environment
  
  [ "$status" -eq 0 ]
}

@test "accepts valid configuration with optional reviewers" {
  set_valid_config
  export AZURE_DEVOPS_REVIEWERS="guid-1,guid-2,guid-3"
  
  run validate_environment
  
  [ "$status" -eq 0 ]
}

@test "accepts valid configuration with optional target branch" {
  set_valid_config
  export AZURE_DEVOPS_TARGET_BRANCH="develop"
  
  run validate_environment
  
  [ "$status" -eq 0 ]
}

@test "accepts valid configuration with debug enabled" {
  set_valid_config
  export AZURE_DEVOPS_DEBUG="true"
  
  run validate_environment
  
  [ "$status" -eq 0 ]
}

@test "accepts valid configuration with all optional variables" {
  set_valid_config
  export AZURE_DEVOPS_REVIEWERS="guid-1,guid-2"
  export AZURE_DEVOPS_TARGET_BRANCH="develop"
  export AZURE_DEVOPS_DEBUG="true"
  
  run validate_environment
  
  [ "$status" -eq 0 ]
}

# ==============================================================================
# Tests: Missing Required Variables
# ==============================================================================

@test "rejects missing AZURE_DEVOPS_ORG" {
  clear_all_config
  export AZURE_DEVOPS_PROJECT="test-project"
  export AZURE_DEVOPS_PAT="abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOP"
  
  run validate_environment
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "AZURE_DEVOPS_ORG is required" ]]
}

@test "rejects missing AZURE_DEVOPS_PROJECT" {
  clear_all_config
  export AZURE_DEVOPS_ORG="test-org"
  export AZURE_DEVOPS_PAT="abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOP"
  
  run validate_environment
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "AZURE_DEVOPS_PROJECT is required" ]]
}

@test "rejects missing AZURE_DEVOPS_PAT" {
  clear_all_config
  export AZURE_DEVOPS_ORG="test-org"
  export AZURE_DEVOPS_PROJECT="test-project"
  
  run validate_environment
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "AZURE_DEVOPS_PAT is required" ]]
}

@test "rejects when all required variables are missing" {
  clear_all_config
  
  run validate_environment
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "AZURE_DEVOPS_ORG is required" ]]
  [[ "$output" =~ "AZURE_DEVOPS_PROJECT is required" ]]
  [[ "$output" =~ "AZURE_DEVOPS_PAT is required" ]]
}

# ==============================================================================
# Tests: Empty Variables
# ==============================================================================

@test "rejects empty AZURE_DEVOPS_ORG" {
  clear_all_config
  export AZURE_DEVOPS_ORG=""
  export AZURE_DEVOPS_PROJECT="test-project"
  export AZURE_DEVOPS_PAT="abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOP"
  
  run validate_environment
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "AZURE_DEVOPS_ORG is required" ]]
}

@test "rejects empty AZURE_DEVOPS_PROJECT" {
  clear_all_config
  export AZURE_DEVOPS_ORG="test-org"
  export AZURE_DEVOPS_PROJECT=""
  export AZURE_DEVOPS_PAT="abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOP"
  
  run validate_environment
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "AZURE_DEVOPS_PROJECT is required" ]]
}

@test "rejects empty AZURE_DEVOPS_PAT" {
  clear_all_config
  export AZURE_DEVOPS_ORG="test-org"
  export AZURE_DEVOPS_PROJECT="test-project"
  export AZURE_DEVOPS_PAT=""
  
  run validate_environment
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "AZURE_DEVOPS_PAT is required" ]]
}

# ==============================================================================
# Tests: PAT Validation
# ==============================================================================

@test "rejects PAT that is too short (less than 20 chars)" {
  clear_all_config
  export AZURE_DEVOPS_ORG="test-org"
  export AZURE_DEVOPS_PROJECT="test-project"
  export AZURE_DEVOPS_PAT="short-pat"  # Only 9 characters
  
  run validate_environment
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "AZURE_DEVOPS_PAT appears invalid" ]]
  [[ "$output" =~ "too short" ]]
}

@test "accepts PAT with exactly 20 characters (minimum)" {
  clear_all_config
  export AZURE_DEVOPS_ORG="test-org"
  export AZURE_DEVOPS_PROJECT="test-project"
  export AZURE_DEVOPS_PAT="12345678901234567890"  # Exactly 20 characters
  
  run validate_environment
  
  [ "$status" -eq 0 ]
}

@test "accepts PAT with 52 characters (typical length)" {
  clear_all_config
  export AZURE_DEVOPS_ORG="test-org"
  export AZURE_DEVOPS_PROJECT="test-project"
  export AZURE_DEVOPS_PAT="abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOP"
  
  run validate_environment
  
  [ "$status" -eq 0 ]
}

# ==============================================================================
# Tests: Error Messages Contain Helpful Information
# ==============================================================================

@test "error message includes setup instructions" {
  clear_all_config
  
  run validate_environment
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "export AZURE_DEVOPS_ORG" ]]
}

@test "PAT error includes link to token settings" {
  clear_all_config
  export AZURE_DEVOPS_ORG="test-org"
  export AZURE_DEVOPS_PROJECT="test-project"
  export AZURE_DEVOPS_PAT="too-short"
  
  run validate_environment
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "_usersSettings/tokens" ]]
}

@test "PAT error includes required scopes" {
  clear_all_config
  export AZURE_DEVOPS_ORG="test-org"
  export AZURE_DEVOPS_PROJECT="test-project"
  export AZURE_DEVOPS_PAT="too-short"
  
  run validate_environment
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "vso.work" ]]
  [[ "$output" =~ "vso.code_write" ]]
  [[ "$output" =~ "vso.work_write" ]]
}

# ==============================================================================
# Tests: Helper Functions
# ==============================================================================

@test "get_config returns variable value when set" {
  export AZURE_DEVOPS_TARGET_BRANCH="develop"
  
  result=$(get_config "AZURE_DEVOPS_TARGET_BRANCH" "main")
  
  [ "$result" = "develop" ]
}

@test "get_config returns default when variable is not set" {
  unset AZURE_DEVOPS_TARGET_BRANCH
  
  result=$(get_config "AZURE_DEVOPS_TARGET_BRANCH" "main")
  
  [ "$result" = "main" ]
}

@test "get_config returns empty string when no default provided" {
  unset AZURE_DEVOPS_TARGET_BRANCH
  
  result=$(get_config "AZURE_DEVOPS_TARGET_BRANCH")
  
  [ "$result" = "" ]
}

@test "is_debug_enabled returns true when debug is set to true" {
  export AZURE_DEVOPS_DEBUG="true"
  
  run is_debug_enabled
  
  [ "$status" -eq 0 ]
}

@test "is_debug_enabled returns false when debug is not set" {
  unset AZURE_DEVOPS_DEBUG
  
  run is_debug_enabled
  
  [ "$status" -eq 1 ]
}

@test "is_debug_enabled returns false when debug is set to false" {
  export AZURE_DEVOPS_DEBUG="false"
  
  run is_debug_enabled
  
  [ "$status" -eq 1 ]
}

@test "get_azure_base_url returns correct URL format" {
  export AZURE_DEVOPS_ORG="my-org"
  export AZURE_DEVOPS_PROJECT="my-project"
  
  result=$(get_azure_base_url)
  
  [ "$result" = "https://dev.azure.com/my-org/my-project" ]
}

@test "get_pat_settings_url returns correct URL format" {
  export AZURE_DEVOPS_ORG="my-org"
  
  result=$(get_pat_settings_url)
  
  [ "$result" = "https://dev.azure.com/my-org/_usersSettings/tokens" ]
}

# ==============================================================================
# Tests: Logging Functions
# ==============================================================================

@test "info outputs message with emoji" {
  run info "Test message"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ℹ️" ]]
  [[ "$output" =~ "Test message" ]]
}

@test "warn outputs message to stderr with emoji" {
  run warn "Warning message"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "⚠️" ]]
  [[ "$output" =~ "Warning message" ]]
}

@test "error outputs message to stderr with emoji" {
  run error "Error message"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "❌" ]]
  [[ "$output" =~ "Error message" ]]
}

@test "success outputs message with checkmark" {
  run success "Success message"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "✓" ]]
  [[ "$output" =~ "Success message" ]]
}

@test "debug outputs nothing when debug is disabled" {
  export AZURE_DEVOPS_DEBUG="false"
  
  run debug "Debug message"
  
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "debug outputs message when debug is enabled" {
  export AZURE_DEVOPS_DEBUG="true"
  
  run debug "Debug message"
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "[DEBUG]" ]]
  [[ "$output" =~ "Debug message" ]]
}

# ==============================================================================
# Tests: Security - PAT Should Never Be Logged
# ==============================================================================

@test "PAT value is never included in error output" {
  clear_all_config
  export AZURE_DEVOPS_ORG="test-org"
  export AZURE_DEVOPS_PROJECT="test-project"
  export AZURE_DEVOPS_PAT="my-secret-pat-value-that-should-never-appear"
  
  # This should succeed, but let's check the output anyway
  run validate_environment
  
  # The actual PAT value should never appear in output
  [[ ! "$output" =~ "my-secret-pat-value-that-should-never-appear" ]]
}

@test "PAT value is not logged even in debug mode" {
  clear_all_config
  export AZURE_DEVOPS_ORG="test-org"
  export AZURE_DEVOPS_PROJECT="test-project"
  export AZURE_DEVOPS_PAT="super-secret-token-12345678901234567890"
  export AZURE_DEVOPS_DEBUG="true"
  
  run validate_environment
  
  # The actual PAT value should never appear in output
  [[ ! "$output" =~ "super-secret-token-12345678901234567890" ]]
}
