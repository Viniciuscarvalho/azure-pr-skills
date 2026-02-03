#!/usr/bin/env bats
# File: ~/.claude/skills/azure-devops-pr/tests/unit/test_git_utils.bats
# Unit tests for the Git utilities module
# Run with: bats tests/unit/test_git_utils.bats

# ==============================================================================
# Test Setup and Teardown
# ==============================================================================

setup() {
  # Get the directory containing this test file
  BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
  SKILL_DIR="${BATS_TEST_DIR}/../.."
  
  # Create a temporary directory for test repos
  TEST_TEMP_DIR=$(mktemp -d)
  
  # Set up test environment variables
  export AZURE_DEVOPS_ORG="test-org"
  export AZURE_DEVOPS_PROJECT="test-project"
  export AZURE_DEVOPS_PAT="test-pat-12345678901234567890"
  export AZURE_DEVOPS_DEBUG="false"
  
  # Load modules
  source "${SKILL_DIR}/lib/config.sh"
  source "${SKILL_DIR}/lib/git-utils.sh"
}

teardown() {
  # Clean up temporary directory
  if [[ -d "$TEST_TEMP_DIR" ]]; then
    rm -rf "$TEST_TEMP_DIR"
  fi
}

# ==============================================================================
# Helper Functions
# ==============================================================================

# Create a temporary git repository with origin remote
# Args: $1 = directory name, $2 = default branch name (optional, default: main)
create_test_repo() {
  local repo_name="${1:-test-repo}"
  local default_branch="${2:-main}"
  local repo_dir="${TEST_TEMP_DIR}/${repo_name}"
  
  mkdir -p "$repo_dir"
  cd "$repo_dir"
  
  git init --initial-branch="$default_branch" -q
  git config user.email "test@test.com"
  git config user.name "Test User"
  
  # Create initial commit
  echo "# Test Repo" > README.md
  git add README.md
  git commit -m "Initial commit" -q
  
  # Create a bare remote
  local remote_dir="${TEST_TEMP_DIR}/${repo_name}-remote.git"
  git clone --bare "$repo_dir" "$remote_dir" -q
  
  # Add origin remote pointing to bare repo
  git remote add origin "$remote_dir" 2>/dev/null || git remote set-url origin "$remote_dir"
  
  echo "$repo_dir"
}

# Create a test repo with Azure DevOps-style remote URL
create_azure_devops_repo() {
  local repo_name="${1:-azure-repo}"
  local repo_dir="${TEST_TEMP_DIR}/${repo_name}"
  
  mkdir -p "$repo_dir"
  cd "$repo_dir"
  
  git init --initial-branch=main -q
  git config user.email "test@test.com"
  git config user.name "Test User"
  
  echo "# Azure Repo" > README.md
  git add README.md
  git commit -m "Initial commit" -q
  
  # Create bare remote
  local remote_dir="${TEST_TEMP_DIR}/${repo_name}-remote.git"
  git clone --bare "$repo_dir" "$remote_dir" -q
  
  # Set origin to Azure DevOps-style URL (fake, but for parsing tests)
  git remote add origin "https://dev.azure.com/org/project/_git/${repo_name}" 2>/dev/null || \
    git remote set-url origin "https://dev.azure.com/org/project/_git/${repo_name}"
  
  # Also set up the actual bare repo as a secondary remote for operations
  git remote add local-origin "$remote_dir" 2>/dev/null || true
  
  echo "$repo_dir"
}

# Add a commit to the current repo
add_test_commit() {
  local message="${1:-Test commit}"
  local random_suffix="${RANDOM}${RANDOM}"
  local file_name="${2:-file-${random_suffix}.txt}"
  
  echo "Content: ${message} at $(date +%s%N)" > "$file_name"
  git add "$file_name"
  git commit -m "$message" -q
}

# ==============================================================================
# Tests: Repository Validation
# ==============================================================================

@test "validate_git_repo succeeds in valid git repository" {
  repo_dir=$(create_test_repo "valid-repo")
  cd "$repo_dir"
  
  run validate_git_repo
  
  [ "$status" -eq 0 ]
}

@test "validate_git_repo fails when not in git repository" {
  # Create a non-git directory
  local non_git_dir="${TEST_TEMP_DIR}/not-a-repo"
  mkdir -p "$non_git_dir"
  cd "$non_git_dir"
  
  run validate_git_repo
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Not a git repository" ]]
}

@test "validate_git_repo fails when no remote origin" {
  # Create git repo without remote
  local repo_dir="${TEST_TEMP_DIR}/no-remote"
  mkdir -p "$repo_dir"
  cd "$repo_dir"
  
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test User"
  echo "test" > test.txt
  git add test.txt
  git commit -m "test" -q
  
  run validate_git_repo
  
  [ "$status" -eq 2 ]
  [[ "$output" =~ "No git remote" ]] || [[ "$output" =~ "origin" ]]
}

@test "validate_git_repo warns about uncommitted changes" {
  repo_dir=$(create_test_repo "uncommitted-repo")
  cd "$repo_dir"
  
  # Create uncommitted changes
  echo "modified" >> README.md
  
  run validate_git_repo
  
  # Should succeed but with warning
  [ "$status" -eq 0 ]
  [[ "$output" =~ "uncommitted" ]]
}

@test "has_uncommitted_changes detects staged changes" {
  repo_dir=$(create_test_repo "staged-repo")
  cd "$repo_dir"
  
  # Stage a change
  echo "new content" > newfile.txt
  git add newfile.txt
  
  run has_uncommitted_changes
  
  [ "$status" -eq 0 ]
}

@test "has_uncommitted_changes detects unstaged changes" {
  repo_dir=$(create_test_repo "unstaged-repo")
  cd "$repo_dir"
  
  # Modify tracked file without staging
  echo "modified" >> README.md
  
  run has_uncommitted_changes
  
  [ "$status" -eq 0 ]
}

@test "has_uncommitted_changes returns 1 for clean repo" {
  repo_dir=$(create_test_repo "clean-repo")
  cd "$repo_dir"
  
  run has_uncommitted_changes
  
  [ "$status" -eq 1 ]
}

# ==============================================================================
# Tests: Branch Detection
# ==============================================================================

@test "get_default_branch detects main branch" {
  repo_dir=$(create_test_repo "main-repo" "main")
  cd "$repo_dir"
  
  # Push to set up tracking
  git push -u origin main -q 2>/dev/null || true
  
  result=$(get_default_branch)
  
  [ "$result" = "main" ]
}

@test "get_default_branch detects master branch" {
  repo_dir=$(create_test_repo "master-repo" "master")
  cd "$repo_dir"
  
  git push -u origin master -q 2>/dev/null || true
  
  result=$(get_default_branch)
  
  [ "$result" = "master" ]
}

@test "get_current_branch returns current branch name" {
  repo_dir=$(create_test_repo "branch-test")
  cd "$repo_dir"
  
  git checkout -b feature-branch -q
  
  result=$(get_current_branch)
  
  [ "$result" = "feature-branch" ]
}

@test "get_current_branch fails in detached HEAD" {
  repo_dir=$(create_test_repo "detached-test")
  cd "$repo_dir"
  
  # Create detached HEAD
  git checkout HEAD~0 -q 2>/dev/null || git checkout --detach -q
  
  run get_current_branch
  
  [ "$status" -eq 1 ]
}

@test "branch_exists_locally returns 0 for existing branch" {
  repo_dir=$(create_test_repo "local-branch-test")
  cd "$repo_dir"
  
  git checkout -b test-branch -q
  
  run branch_exists_locally "test-branch"
  
  [ "$status" -eq 0 ]
}

@test "branch_exists_locally returns 1 for non-existing branch" {
  repo_dir=$(create_test_repo "no-branch-test")
  cd "$repo_dir"
  
  run branch_exists_locally "non-existent-branch"
  
  [ "$status" -eq 1 ]
}

# ==============================================================================
# Tests: Kebab Case Conversion
# ==============================================================================

@test "to_kebab_case converts title correctly" {
  result=$(to_kebab_case "Fix Authentication Timeout in API")
  
  [ "$result" = "fix-authentication-timeout-in-api" ]
}

@test "to_kebab_case handles special characters" {
  result=$(to_kebab_case "Bug: Fix #123 - API Error!")
  
  [ "$result" = "bug-fix-123-api-error" ]
}

@test "to_kebab_case collapses multiple hyphens" {
  result=$(to_kebab_case "Fix   Multiple   Spaces")
  
  [ "$result" = "fix-multiple-spaces" ]
}

@test "to_kebab_case removes leading and trailing hyphens" {
  result=$(to_kebab_case "  Leading and Trailing  ")
  
  [ "$result" = "leading-and-trailing" ]
}

@test "to_kebab_case limits length to 50 characters by default" {
  result=$(to_kebab_case "This is a very long title that should be truncated because it exceeds the maximum length allowed")
  
  [ ${#result} -le 50 ]
}

@test "to_kebab_case accepts custom max length" {
  result=$(to_kebab_case "Long title here" 10)
  
  [ ${#result} -le 10 ]
}

@test "to_kebab_case handles numbers" {
  result=$(to_kebab_case "Task 123 Fix Bug 456")
  
  [ "$result" = "task-123-fix-bug-456" ]
}

@test "to_kebab_case handles unicode characters" {
  result=$(to_kebab_case "Fix açãõ and é character")
  
  # Unicode chars should be replaced with hyphens
  [[ ! "$result" =~ [çãõé] ]]
}

# ==============================================================================
# Tests: Branch Name Generation
# ==============================================================================

@test "generate_branch_name creates correct format" {
  result=$(generate_branch_name "12345" "Fix login bug")
  
  [ "$result" = "feature/WI-12345-fix-login-bug" ]
}

@test "generate_branch_name uses custom prefix" {
  result=$(generate_branch_name "12345" "Fix bug" "bugfix")
  
  [ "$result" = "bugfix/WI-12345-fix-bug" ]
}

@test "generate_branch_name truncates long titles" {
  result=$(generate_branch_name "12345" "This is a very long title that should be truncated")
  
  # WI-12345- is 9 chars, so title portion should be limited
  [[ ${#result} -lt 80 ]]
}

@test "is_valid_branch_name accepts valid names" {
  run is_valid_branch_name "feature/WI-12345-fix-bug"
  [ "$status" -eq 0 ]
  
  run is_valid_branch_name "simple-branch"
  [ "$status" -eq 0 ]
  
  run is_valid_branch_name "feature/test"
  [ "$status" -eq 0 ]
}

@test "is_valid_branch_name rejects invalid names" {
  run is_valid_branch_name ""
  [ "$status" -eq 1 ]
  
  run is_valid_branch_name "-starts-with-hyphen"
  [ "$status" -eq 1 ]
  
  run is_valid_branch_name "has..double-dots"
  [ "$status" -eq 1 ]
}

# ==============================================================================
# Tests: Branch Validation
# ==============================================================================

@test "validate_current_branch succeeds when branch has commits ahead" {
  repo_dir=$(create_test_repo "ahead-repo")
  cd "$repo_dir"
  
  # Push main to origin
  git push -u origin main -q 2>/dev/null || true
  
  # Create feature branch and add commit
  git checkout -b feature-test -q
  add_test_commit "Feature commit"
  
  run validate_current_branch
  
  [ "$status" -eq 0 ]
  [[ "$output" =~ "feature-test" ]]
}

@test "validate_current_branch fails when no commits ahead" {
  repo_dir=$(create_test_repo "no-ahead-repo")
  cd "$repo_dir"
  
  # Push main to origin
  git push -u origin main -q 2>/dev/null || true
  
  # Create feature branch WITHOUT adding commits
  git checkout -b feature-no-commits -q
  
  run validate_current_branch
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "no commits" ]]
}

@test "validate_current_branch fails in detached HEAD" {
  repo_dir=$(create_test_repo "detached-head-repo")
  cd "$repo_dir"
  
  # Create detached HEAD state
  git checkout --detach -q
  
  run validate_current_branch
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "detached" ]] || [[ "$output" =~ "Not on any branch" ]]
}

@test "validate_current_branch fails when on base branch" {
  repo_dir=$(create_test_repo "on-main-repo")
  cd "$repo_dir"
  
  # Push main
  git push -u origin main -q 2>/dev/null || true
  
  # Stay on main
  run validate_current_branch
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Cannot create PR" ]] || [[ "$output" =~ "itself" ]]
}

@test "get_commits_ahead returns correct count" {
  repo_dir=$(create_test_repo "commits-ahead-repo")
  cd "$repo_dir"
  
  git push -u origin main -q 2>/dev/null || true
  
  git checkout -b test-ahead -q
  add_test_commit "Commit 1"
  add_test_commit "Commit 2"
  add_test_commit "Commit 3"
  
  result=$(get_commits_ahead)
  
  [ "$result" -eq 3 ]
}

# ==============================================================================
# Tests: Utility Functions
# ==============================================================================

@test "get_repository_name extracts name from HTTPS URL" {
  repo_dir=$(create_azure_devops_repo "my-awesome-repo")
  cd "$repo_dir"
  
  # Set URL explicitly
  git remote set-url origin "https://dev.azure.com/org/project/_git/my-awesome-repo"
  
  result=$(get_repository_name)
  
  [ "$result" = "my-awesome-repo" ]
}

@test "get_repository_name handles .git suffix" {
  repo_dir=$(create_test_repo "repo-with-git-suffix")
  cd "$repo_dir"
  
  # The remote is a bare .git directory
  result=$(get_repository_name)
  
  # Should strip .git suffix
  [[ ! "$result" =~ \.git$ ]]
}

@test "get_head_short_hash returns short hash" {
  repo_dir=$(create_test_repo "hash-repo")
  cd "$repo_dir"
  
  result=$(get_head_short_hash)
  
  # Short hash should be 7-10 characters
  [ ${#result} -ge 7 ]
  [ ${#result} -le 10 ]
}

@test "get_last_commit_message returns message" {
  repo_dir=$(create_test_repo "message-repo")
  cd "$repo_dir"
  
  add_test_commit "This is my test commit message"
  
  result=$(get_last_commit_message)
  
  [ "$result" = "This is my test commit message" ]
}

@test "has_commits returns 0 when repo has commits" {
  repo_dir=$(create_test_repo "has-commits-repo")
  cd "$repo_dir"
  
  run has_commits
  
  [ "$status" -eq 0 ]
}

@test "get_total_commits returns correct count" {
  repo_dir=$(create_test_repo "count-commits-repo")
  cd "$repo_dir"
  
  add_test_commit "Second commit"
  add_test_commit "Third commit"
  
  result=$(get_total_commits)
  
  # Initial + 2 added = 3
  [ "$result" -eq 3 ]
}

# ==============================================================================
# Tests: Non-Interactive Branch Creation
# ==============================================================================

@test "create_feature_branch_noninteractive creates branch correctly" {
  repo_dir=$(create_test_repo "noninteractive-repo")
  cd "$repo_dir"
  
  # Push and fetch to ensure remote tracking is set up
  git push -u origin main -q 2>/dev/null || true
  git fetch origin -q 2>/dev/null || true
  
  result=$(create_feature_branch_noninteractive "12345" "Fix the bug")
  
  [ "$result" = "feature/WI-12345-fix-the-bug" ]
  
  # Verify we're on the new branch
  current=$(git branch --show-current)
  [ "$current" = "feature/WI-12345-fix-the-bug" ]
}

@test "create_feature_branch_noninteractive accepts custom name" {
  repo_dir=$(create_test_repo "custom-name-repo")
  cd "$repo_dir"
  
  # Push and fetch to ensure remote tracking is set up
  git push -u origin main -q 2>/dev/null || true
  git fetch origin -q 2>/dev/null || true
  
  result=$(create_feature_branch_noninteractive "12345" "Fix bug" "my-custom-branch")
  
  [ "$result" = "my-custom-branch" ]
}

@test "create_feature_branch_noninteractive fails if branch exists" {
  repo_dir=$(create_test_repo "exists-repo")
  cd "$repo_dir"
  
  git push -u origin main -q 2>/dev/null || true
  git fetch origin -q 2>/dev/null || true
  
  # Create branch first
  git checkout -b "feature/WI-12345-existing" -q
  git checkout main -q
  
  run create_feature_branch_noninteractive "12345" "existing"
  
  [ "$status" -eq 1 ]
}
