# Azure DevOps PR Skill - Test Suite

This directory contains the automated test suite for the Azure DevOps PR Automation Skill.

## Prerequisites

### Install bats-core

**macOS (Homebrew):**
```bash
brew install bats-core
```

**npm (cross-platform):**
```bash
npm install -g bats
```

**Linux (apt):**
```bash
sudo apt-get install bats
```

**Verify installation:**
```bash
bats --version
```

## Directory Structure

```
tests/
├── README.md              # This file
├── run_tests.sh           # CI script to run all tests
├── unit/                  # Unit tests (test individual modules)
│   ├── test_config.bats        # Tests for lib/config.sh (34 tests)
│   ├── test_azure_client.bats  # Tests for lib/azure-client.sh (37 tests)
│   ├── test_git_utils.bats     # Tests for lib/git-utils.sh (40 tests)
│   └── test_ui.bats            # Tests for lib/ui.sh (42 tests)
└── integration/           # Integration tests (end-to-end flows)
    └── test_full_workflow.bats # Full workflow tests (20 tests)
```

## Running Tests

### Run All Tests

```bash
# From the skill directory
cd ~/.claude/skills/azure-devops-pr

# Run all tests
./tests/run_tests.sh

# Or directly with bats
bats tests/unit/*.bats tests/integration/*.bats
```

### Run Unit Tests Only

```bash
./tests/run_tests.sh --unit

# Or
bats tests/unit/*.bats
```

### Run Integration Tests Only

```bash
./tests/run_tests.sh --integration

# Or
bats tests/integration/*.bats
```

### Run Specific Test File

```bash
bats tests/unit/test_config.bats
```

### Run in Verbose Mode

```bash
./tests/run_tests.sh --verbose

# Or
bats --verbose-run tests/unit/*.bats
```

### Show Coverage Summary

```bash
./tests/run_tests.sh --coverage
```

## Test Coverage

| Module | Test File | Tests | Coverage |
|--------|-----------|-------|----------|
| config.sh | test_config.bats | 34 | ✅ High |
| azure-client.sh | test_azure_client.bats | 37 | ✅ High |
| git-utils.sh | test_git_utils.bats | 40 | ✅ High |
| ui.sh | test_ui.bats | 42 | ✅ High |
| Full Workflow | test_full_workflow.bats | 20 | ✅ High |
| **Total** | | **173** | **>70%** |

## Writing New Tests

### Test File Structure

```bash
#!/usr/bin/env bats
# tests/unit/test_example.bats

# Setup runs before each test
setup() {
  # Get test directory
  BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  
  # Set required environment variables
  export AZURE_DEVOPS_ORG="test-org"
  export AZURE_DEVOPS_PROJECT="test-project"
  export AZURE_DEVOPS_PAT="test-pat-12345678901234567890"
  
  # Source the module being tested
  source "${BATS_TEST_DIR}/../../lib/example.sh"
}

# Teardown runs after each test
teardown() {
  # Cleanup any temporary resources
}

# Test case
@test "function does something expected" {
  run some_function "arg1" "arg2"
  
  # Check exit code
  [ "$status" -eq 0 ]
  
  # Check output
  [[ "$output" =~ "expected text" ]]
}
```

### Mocking Curl

```bash
@test "handles API errors correctly" {
  # Create mock curl that returns error
  curl() {
    echo '{"error": "not found"}'
    echo "404"
  }
  export -f curl
  
  run azure_api_call "GET" "/test"
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "404" ]]
}
```

### Using Temporary Git Repos

```bash
setup() {
  # Create temp directory
  TEST_TEMP_DIR=$(mktemp -d)
  cd "$TEST_TEMP_DIR"
  
  # Initialize git repo
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test User"
  
  # Add remote
  git remote add origin "https://dev.azure.com/org/project/_git/repo"
}

teardown() {
  # Cleanup temp directory
  rm -rf "$TEST_TEMP_DIR"
}
```

## Debugging Failing Tests

### Run Single Test in Verbose Mode

```bash
bats --verbose-run tests/unit/test_config.bats --filter "specific test name"
```

### Print Debug Information

Add to your test:
```bash
@test "debug example" {
  echo "Debug: some_variable = $some_variable" >&3
  
  run some_function
  
  echo "Status: $status" >&3
  echo "Output: $output" >&3
  
  [ "$status" -eq 0 ]
}
```

### Check Test Output

```bash
# Run test and see all output
bats tests/unit/test_config.bats 2>&1
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install bats
        run: |
          sudo apt-get update
          sudo apt-get install -y bats
      - name: Run tests
        run: ./tests/run_tests.sh
```

### Exit Codes

The test runner uses standard exit codes:
- `0`: All tests passed
- `1`: One or more tests failed

## Test Categories

### Unit Tests

Unit tests verify individual functions in isolation:

- **test_config.bats**: Environment validation, logging functions
- **test_azure_client.bats**: API calls, retry logic, error handling
- **test_git_utils.bats**: Repository validation, branch operations
- **test_ui.bats**: User prompts, output formatting

### Integration Tests

Integration tests verify the complete workflow:

- **test_full_workflow.bats**: End-to-end PR creation with mocked API

## Mocking Strategy

| Component | Mock Method |
|-----------|-------------|
| Azure API | Function override for `curl` |
| Git repos | Temporary directories with `git init` |
| User input | Echo piped to stdin |
| File system | Temporary directories |

## Common Issues

### "bats: command not found"

Install bats-core using the instructions above.

### "Permission denied" on run_tests.sh

```bash
chmod +x tests/run_tests.sh
```

### Tests pass locally but fail in CI

- Check if all required environment variables are set
- Verify git configuration (`user.email`, `user.name`)
- Ensure temp directories are being cleaned up

### Git tests failing

- Make sure `git` is installed
- Check that you're not running tests inside an existing git repo
- Verify temp directory creation permissions

---

For more information, see the main project documentation.
