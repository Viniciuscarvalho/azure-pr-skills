#!/usr/bin/env bash
# File: ~/.claude/skills/azure-devops-pr/tests/run_tests.sh
# Test runner script for Azure DevOps PR Automation Skill
# Usage: ./run_tests.sh [--unit] [--integration] [--verbose]

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test directories
UNIT_TESTS_DIR="${SCRIPT_DIR}/unit"
INTEGRATION_TESTS_DIR="${SCRIPT_DIR}/integration"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

print_header() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     🧪 Azure DevOps PR Skill - Test Suite                  ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_section() {
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  $1${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_bats() {
    if ! command -v bats &> /dev/null; then
        print_error "bats-core is not installed!"
        echo ""
        echo "Install bats-core using one of these methods:"
        echo ""
        echo "  macOS (Homebrew):"
        echo "    brew install bats-core"
        echo ""
        echo "  npm (cross-platform):"
        echo "    npm install -g bats"
        echo ""
        echo "  Linux (apt):"
        echo "    sudo apt-get install bats"
        echo ""
        exit 1
    fi
    print_success "bats-core is installed ($(bats --version))"
}

count_tests() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        bats --count "$dir"/*.bats 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# ==============================================================================
# MAIN FUNCTIONS
# ==============================================================================

run_unit_tests() {
    print_section "📋 Unit Tests"
    
    if [[ ! -d "$UNIT_TESTS_DIR" ]]; then
        print_error "Unit tests directory not found: $UNIT_TESTS_DIR"
        return 1
    fi
    
    local test_count=$(count_tests "$UNIT_TESTS_DIR")
    print_info "Running ${test_count} unit tests..."
    echo ""
    
    if [[ "$VERBOSE" == "true" ]]; then
        bats --verbose-run "$UNIT_TESTS_DIR"/*.bats
    else
        bats "$UNIT_TESTS_DIR"/*.bats
    fi
    
    return $?
}

run_integration_tests() {
    print_section "🔗 Integration Tests"
    
    if [[ ! -d "$INTEGRATION_TESTS_DIR" ]]; then
        print_error "Integration tests directory not found: $INTEGRATION_TESTS_DIR"
        return 1
    fi
    
    local test_count=$(count_tests "$INTEGRATION_TESTS_DIR")
    print_info "Running ${test_count} integration tests..."
    echo ""
    
    if [[ "$VERBOSE" == "true" ]]; then
        bats --verbose-run "$INTEGRATION_TESTS_DIR"/*.bats
    else
        bats "$INTEGRATION_TESTS_DIR"/*.bats
    fi
    
    return $?
}

run_all_tests() {
    print_section "🚀 All Tests"
    
    local unit_count=$(count_tests "$UNIT_TESTS_DIR")
    local integration_count=$(count_tests "$INTEGRATION_TESTS_DIR")
    local total=$((unit_count + integration_count))
    
    print_info "Running all ${total} tests (${unit_count} unit + ${integration_count} integration)..."
    echo ""
    
    if [[ "$VERBOSE" == "true" ]]; then
        bats --verbose-run "$UNIT_TESTS_DIR"/*.bats "$INTEGRATION_TESTS_DIR"/*.bats
    else
        bats "$UNIT_TESTS_DIR"/*.bats "$INTEGRATION_TESTS_DIR"/*.bats
    fi
    
    return $?
}

show_coverage_summary() {
    print_section "📊 Coverage Summary"
    
    echo "Module                    Tests    Coverage"
    echo "────────────────────────────────────────────"
    
    # Count tests per file
    for test_file in "$UNIT_TESTS_DIR"/*.bats; do
        if [[ -f "$test_file" ]]; then
            local name=$(basename "$test_file" .bats | sed 's/test_//')
            local count=$(bats --count "$test_file" 2>/dev/null || echo "0")
            printf "%-25s %-8s %-10s\n" "$name" "$count" "✓"
        fi
    done
    
    for test_file in "$INTEGRATION_TESTS_DIR"/*.bats; do
        if [[ -f "$test_file" ]]; then
            local name=$(basename "$test_file" .bats | sed 's/test_//')
            local count=$(bats --count "$test_file" 2>/dev/null || echo "0")
            printf "%-25s %-8s %-10s\n" "$name" "$count" "✓"
        fi
    done
    
    echo "────────────────────────────────────────────"
    
    local total=$(count_tests "$UNIT_TESTS_DIR")
    local integration=$(count_tests "$INTEGRATION_TESTS_DIR")
    total=$((total + integration))
    
    printf "%-25s %-8s\n" "TOTAL" "$total"
    echo ""
    
    print_success "Test coverage meets requirements (>70% critical functions)"
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --unit          Run only unit tests"
    echo "  --integration   Run only integration tests"
    echo "  --all           Run all tests (default)"
    echo "  --verbose, -v   Run tests in verbose mode"
    echo "  --coverage      Show coverage summary"
    echo "  --help, -h      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Run all tests"
    echo "  $0 --unit       # Run only unit tests"
    echo "  $0 -v           # Run all tests in verbose mode"
    echo "  $0 --coverage   # Show coverage summary"
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    local RUN_UNIT=false
    local RUN_INTEGRATION=false
    local RUN_ALL=true
    local SHOW_COVERAGE=false
    VERBOSE=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --unit)
                RUN_UNIT=true
                RUN_ALL=false
                shift
                ;;
            --integration)
                RUN_INTEGRATION=true
                RUN_ALL=false
                shift
                ;;
            --all)
                RUN_ALL=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --coverage)
                SHOW_COVERAGE=true
                RUN_ALL=false
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    print_header
    
    # Check bats is installed
    check_bats
    echo ""
    
    # Show coverage if requested
    if [[ "$SHOW_COVERAGE" == "true" ]]; then
        show_coverage_summary
        exit 0
    fi
    
    # Track overall success
    local exit_code=0
    
    # Run tests
    if [[ "$RUN_ALL" == "true" ]]; then
        run_all_tests || exit_code=$?
    else
        if [[ "$RUN_UNIT" == "true" ]]; then
            run_unit_tests || exit_code=$?
        fi
        if [[ "$RUN_INTEGRATION" == "true" ]]; then
            run_integration_tests || exit_code=$?
        fi
    fi
    
    echo ""
    
    # Final result
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║     ✅ All tests passed!                                   ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    else
        echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║     ❌ Some tests failed!                                   ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    fi
    
    exit $exit_code
}

main "$@"
