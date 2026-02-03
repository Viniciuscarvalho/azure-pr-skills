#!/usr/bin/env bash
# File: install.sh
# Azure DevOps PR Skill - Installation Script
# Supports macOS and Linux
# Usage: ./install.sh [--uninstall]

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

INSTALL_DIR="$HOME/.claude/skills/azure-devops-pr"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

print_header() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     📦 Azure DevOps PR Skill - Installer                   ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

print_step() {
    echo ""
    echo -e "${BLUE}━━━ $1 ━━━${NC}"
}

check_command() {
    local cmd="$1"
    local name="${2:-$cmd}"
    local install_hint="${3:-}"
    
    if command -v "$cmd" &> /dev/null; then
        local version=$($cmd --version 2>&1 | head -n1)
        print_success "$name found: $version"
        return 0
    else
        print_error "$name not found"
        if [[ -n "$install_hint" ]]; then
            echo "   → Install: $install_hint"
        fi
        return 1
    fi
}

# ==============================================================================
# UNINSTALL FUNCTION
# ==============================================================================

uninstall() {
    print_header
    print_step "Uninstalling Azure DevOps PR Skill"
    
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        print_success "Removed: $INSTALL_DIR"
    else
        print_warning "Installation directory not found: $INSTALL_DIR"
    fi
    
    echo ""
    print_success "Uninstall complete!"
    echo ""
    print_info "Note: Environment variables were not removed."
    echo "   You may want to remove these from ~/.bashrc or ~/.zshrc:"
    echo "   - AZURE_DEVOPS_ORG"
    echo "   - AZURE_DEVOPS_PROJECT"
    echo "   - AZURE_DEVOPS_PAT"
    echo ""
    
    exit 0
}

# ==============================================================================
# MAIN INSTALLATION
# ==============================================================================

install() {
    print_header
    
    # ==== DETECT OS ====
    print_step "Detecting Operating System"
    
    OS="$(uname -s)"
    case "${OS}" in
        Linux*)     MACHINE=Linux;;
        Darwin*)    MACHINE=macOS;;
        *)          MACHINE="UNKNOWN:${OS}"
    esac
    
    if [[ "$MACHINE" == "UNKNOWN"* ]]; then
        print_error "Unsupported operating system: ${OS}"
        echo "This skill supports macOS and Linux only."
        exit 1
    fi
    
    print_success "Detected: $MACHINE"
    
    # ==== CHECK DEPENDENCIES ====
    print_step "Checking Dependencies"
    
    local deps_ok=true
    
    check_command "bash" "Bash" || deps_ok=false
    check_command "curl" "curl" "brew install curl (macOS) or apt-get install curl (Linux)" || deps_ok=false
    check_command "git" "Git" "brew install git (macOS) or apt-get install git (Linux)" || deps_ok=false
    check_command "jq" "jq" "brew install jq (macOS) or apt-get install jq (Linux)" || deps_ok=false
    
    if [[ "$deps_ok" == "false" ]]; then
        echo ""
        print_error "Missing dependencies. Please install them and try again."
        exit 1
    fi
    
    # ==== CREATE DIRECTORIES ====
    print_step "Creating Installation Directory"
    
    print_info "Installing to: $INSTALL_DIR"
    
    mkdir -p "$INSTALL_DIR/lib"
    mkdir -p "$INSTALL_DIR/tests/unit"
    mkdir -p "$INSTALL_DIR/tests/integration"
    mkdir -p "$INSTALL_DIR/docs"
    
    print_success "Directories created"
    
    # ==== COPY FILES ====
    print_step "Copying Files"
    
    # Check if we're running from the source directory
    if [[ -f "${SCRIPT_DIR}/azure-pr.sh" ]]; then
        cp "${SCRIPT_DIR}/azure-pr.sh" "$INSTALL_DIR/"
        print_success "Copied: azure-pr.sh"
    else
        print_warning "azure-pr.sh not found in source directory"
    fi
    
    if [[ -d "${SCRIPT_DIR}/lib" ]]; then
        cp "${SCRIPT_DIR}/lib/"*.sh "$INSTALL_DIR/lib/" 2>/dev/null || true
        print_success "Copied: lib/*.sh"
    fi
    
    if [[ -f "${SCRIPT_DIR}/SKILL.md" ]]; then
        cp "${SCRIPT_DIR}/SKILL.md" "$INSTALL_DIR/"
        print_success "Copied: SKILL.md"
    fi
    
    if [[ -f "${SCRIPT_DIR}/README.md" ]]; then
        cp "${SCRIPT_DIR}/README.md" "$INSTALL_DIR/"
        print_success "Copied: README.md"
    fi
    
    if [[ -d "${SCRIPT_DIR}/tests" ]]; then
        cp -r "${SCRIPT_DIR}/tests/"* "$INSTALL_DIR/tests/" 2>/dev/null || true
        print_success "Copied: tests/"
    fi
    
    if [[ -d "${SCRIPT_DIR}/docs" ]]; then
        cp -r "${SCRIPT_DIR}/docs/"* "$INSTALL_DIR/docs/" 2>/dev/null || true
        print_success "Copied: docs/"
    fi
    
    # ==== MAKE EXECUTABLE ====
    print_step "Setting Permissions"
    
    chmod +x "$INSTALL_DIR/azure-pr.sh" 2>/dev/null || true
    chmod +x "$INSTALL_DIR/tests/run_tests.sh" 2>/dev/null || true
    
    print_success "Made scripts executable"
    
    # ==== CHECK CONFIGURATION ====
    print_step "Checking Configuration"
    
    local need_config=false
    
    if [[ -z "${AZURE_DEVOPS_ORG:-}" ]]; then
        print_warning "AZURE_DEVOPS_ORG not set"
        need_config=true
    else
        print_success "AZURE_DEVOPS_ORG is set: ${AZURE_DEVOPS_ORG}"
    fi
    
    if [[ -z "${AZURE_DEVOPS_PROJECT:-}" ]]; then
        print_warning "AZURE_DEVOPS_PROJECT not set"
        need_config=true
    else
        print_success "AZURE_DEVOPS_PROJECT is set: ${AZURE_DEVOPS_PROJECT}"
    fi
    
    if [[ -z "${AZURE_DEVOPS_PAT:-}" ]]; then
        print_warning "AZURE_DEVOPS_PAT not set"
        need_config=true
    else
        print_success "AZURE_DEVOPS_PAT is set: ***${AZURE_DEVOPS_PAT: -4}"
    fi
    
    # ==== CONFIGURATION INSTRUCTIONS ====
    if [[ "$need_config" == "true" ]]; then
        echo ""
        echo -e "${YELLOW}━━━ Configuration Required ━━━${NC}"
        echo ""
        echo "Add these lines to ~/.bashrc or ~/.zshrc:"
        echo ""
        echo -e "  ${CYAN}export AZURE_DEVOPS_ORG=\"your-organization\"${NC}"
        echo -e "  ${CYAN}export AZURE_DEVOPS_PROJECT=\"your-project\"${NC}"
        echo -e "  ${CYAN}export AZURE_DEVOPS_PAT=\"your-personal-access-token\"${NC}"
        echo ""
        echo "Optional:"
        echo -e "  ${CYAN}export AZURE_DEVOPS_REVIEWERS=\"guid1,guid2\"${NC}"
        echo -e "  ${CYAN}export AZURE_DEVOPS_TARGET_BRANCH=\"develop\"${NC}"
        echo ""
        echo "Create PAT at:"
        echo "  https://dev.azure.com/{org}/_usersSettings/tokens"
        echo ""
        echo "Required PAT scopes:"
        echo "  • vso.work (Work Items - Read)"
        echo "  • vso.work_write (Work Items - Read & Write)"
        echo "  • vso.code_write (Code - Read & Write)"
        echo ""
        echo "See docs/PAT_SETUP.md for detailed instructions."
    fi
    
    # ==== SUCCESS ====
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     ✅ Installation complete!                              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "🚀 Getting Started:"
    echo ""
    echo "   1. Reload your shell (or run: source ~/.bashrc)"
    echo "   2. Navigate to a git repository"
    echo "   3. Run: /azure-pr"
    echo ""
    echo "📖 Documentation: $INSTALL_DIR/README.md"
    echo "🧪 Run tests:     $INSTALL_DIR/tests/run_tests.sh"
    echo "🆘 Troubleshoot:  $INSTALL_DIR/docs/TROUBLESHOOTING.md"
    echo ""
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    # Parse arguments
    case "${1:-}" in
        --uninstall|-u)
            uninstall
            ;;
        --help|-h)
            echo "Usage: $0 [--uninstall | --help]"
            echo ""
            echo "Options:"
            echo "  --uninstall, -u   Remove the skill"
            echo "  --help, -h        Show this help"
            exit 0
            ;;
        "")
            install
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
}

main "$@"
