# Azure DevOps PR Automation Skill

> Automate Pull Request creation in Azure DevOps with automatic Work Item linkage

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)]()
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-173%20passing-brightgreen.svg)]()

## Overview

This Claude Code Skill automates the tedious process of creating Pull Requests in Azure DevOps and linking them to Work Items. Save ~5 minutes per PR by eliminating manual copying of titles, descriptions, and acceptance criteria.

**Before**: Open Azure Boards → find Work Item ID → copy title → copy description → open Azure Repos → create PR → paste everything → add reviewers → link Work Item manually

**After**: Type `/azure-pr` → select Work Item → done! ✨

## Features

| Feature | Description |
|---------|-------------|
| ✅ **Interactive Work Item Selection** | View and select from your active Work Items |
| ✅ **Auto-populated PR** | Title, description, and acceptance criteria from Work Item |
| ✅ **Smart Branch Management** | Create new branch or use current |
| ✅ **Automatic Linkage** | PR and Work Item linked via ArtifactLink |
| ✅ **Draft by Default** | Review before marking ready |
| ✅ **Auto-add Reviewers** | Configure default reviewers once |
| ✅ **Retry Logic** | Handles rate limiting and transient failures |
| ✅ **Clear Feedback** | Loading indicators and helpful error messages |

## Requirements

| Dependency | Minimum Version | Check Command |
|------------|-----------------|---------------|
| **Bash** | 4.0+ | `bash --version` |
| **curl** | 7.68+ | `curl --version` |
| **git** | 2.25+ | `git --version` |
| **jq** | 1.6+ | `jq --version` |

Additionally:
- **Claude Code** CLI installed
- **Azure DevOps** account with:
  - Organization and Project access
  - Personal Access Token (PAT) with scopes: `vso.work`, `vso.code_write`, `vso.work_write`

## Installation

### Quick Install

```bash
# Clone or download this repository, then run:
chmod +x install.sh
./install.sh
```

### Manual Install

1. Create the skill directory:

```bash
mkdir -p ~/.claude/skills/azure-devops-pr/lib
```

2. Copy all files:

```bash
cp azure-pr.sh ~/.claude/skills/azure-devops-pr/
cp lib/*.sh ~/.claude/skills/azure-devops-pr/lib/
cp SKILL.md ~/.claude/skills/azure-devops-pr/
chmod +x ~/.claude/skills/azure-devops-pr/azure-pr.sh
```

3. Configure environment variables (see Configuration below)

## Configuration

### Environment Variables

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# Required
export AZURE_DEVOPS_ORG="your-organization"
export AZURE_DEVOPS_PROJECT="your-project"
export AZURE_DEVOPS_PAT="your-personal-access-token"

# Optional
export AZURE_DEVOPS_REVIEWERS="guid1,guid2"  # Comma-separated reviewer GUIDs
export AZURE_DEVOPS_TARGET_BRANCH="develop"  # Override default (main/master)
export AZURE_DEVOPS_DEBUG="true"             # Enable debug logging

# Advanced (API version override)
export AZURE_API_VERSION="7.1"               # Default: 7.1 (stable)
                                             # Use "7.2-preview" for latest features
```

Reload your shell:
```bash
source ~/.bashrc  # or source ~/.zshrc
```

### Creating a Personal Access Token (PAT)

See [PAT Setup Guide](docs/PAT_SETUP.md) for detailed instructions.

**Quick version:**
1. Go to: `https://dev.azure.com/{your-org}/_usersSettings/tokens`
2. Click "New Token"
3. Name it: "Claude PR Skill"
4. Select scopes:
   - `vso.work` (Work Items - Read)
   - `vso.work_write` (Work Items - Read & Write)
   - `vso.code_write` (Code - Read & Write)
5. Copy token and set `AZURE_DEVOPS_PAT` env var

## Usage

### Basic Workflow

1. Finish coding and commit your changes
2. From your git repository, invoke the skill:

```bash
/azure-pr
```

3. Select a Work Item from the list
4. Choose to create a new branch or use current
5. PR created! 🎉

### Example Session

```
$ /azure-pr

🚀 Azure DevOps PR Automation
──────────────────────────────────────────────────

[1/6] Validating environment...
✓ Environment validated

[2/6] Validating git repository...
✓ Git repository validated

[3/6] Fetching Work Items...
✓ Work Items fetched

📋 Your Active Work Items:

  [1] #12345 [Bug] - Fix timeout in authentication (Active)
  [2] #12346 [Feature] - Add dark mode support (Active)
  [3] #12340 [Task] - Update API documentation (In Progress)

Select Work Item (1-3): 1

📌 Selected Work Item:
   ID:    #12345
   Type:  Bug
   Title: Fix timeout in authentication
   State: Active

[4/6] Branch selection...

🔀 Branch Options:
   new     - Create a new feature branch from this Work Item
   current - Use the current branch (must have commits ahead)

Create new branch or use current? [new/current]: current

✓ Branch: feature/fix-auth-timeout

[5/6] Creating Pull Request...
✓ Branch pushed
✓ Pull Request created (Draft)

[6/6] Finalizing...
✓ Linked to Work Item #12345
✓ Reviewers added

🎉 PR created successfully:
   https://dev.azure.com/myorg/myproject/_git/myrepo/pullrequest/789
```

### Creating a New Branch

When prompted, type `new` to create a branch based on the Work Item:

```
Create new branch or use current? [new/current]: new

Suggested branch name: feature/WI-12345-fix-timeout-in-authentication
Enter to confirm or type a new name: [ENTER]

✓ Branch 'feature/WI-12345-fix-timeout-in-authentication' created
```

## Troubleshooting

See [Troubleshooting Guide](docs/TROUBLESHOOTING.md) for detailed solutions.

**Common Issues:**

| Error | Solution |
|-------|----------|
| `AZURE_DEVOPS_PAT is required` | Set env var in ~/.bashrc |
| `Authentication failed` | Check PAT scopes and expiration |
| `No Work Items found` | Verify Work Items are assigned to you |
| `Branch has no commits ahead` | Make commits or create new branch |
| `Not a git repository` | Run from inside a git repo |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success - PR created |
| 1 | Configuration error (missing env vars) |
| 2 | Git repository error |
| 3 | Azure DevOps API error |
| 4 | User cancelled operation |

## Performance

| Operation | Time |
|-----------|------|
| Work Item fetch | < 3 seconds |
| PR creation | < 5 seconds |
| **Total workflow** | **< 15 seconds** |

Compare to ~5 minutes manually! That's **20x faster**! 🚀

## Project Structure

```
~/.claude/skills/azure-devops-pr/
├── SKILL.md              # Skill definition for Claude Code
├── azure-pr.sh           # Main orchestrator script
├── README.md             # This file
├── lib/
│   ├── config.sh         # Environment validation
│   ├── azure-client.sh   # Azure DevOps API client
│   ├── git-utils.sh      # Git operations
│   └── ui.sh             # Interactive UI components
├── tests/
│   ├── run_tests.sh      # Test runner
│   ├── unit/             # Unit tests
│   └── integration/      # Integration tests
└── docs/
    ├── PAT_SETUP.md      # PAT creation guide
    └── TROUBLESHOOTING.md # Problem solutions
```

## Running Tests

```bash
# Run all tests
./tests/run_tests.sh

# Run only unit tests
./tests/run_tests.sh --unit

# Run with verbose output
./tests/run_tests.sh --verbose

# Show coverage summary
./tests/run_tests.sh --coverage
```

**Test Coverage:** 173 tests passing ✅

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests (`./tests/run_tests.sh`)
5. Commit (`git commit -m 'Add amazing feature'`)
6. Push (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Support

- 🐛 **Bug Reports**: Open an issue
- 💡 **Feature Requests**: Open an issue with `[Feature]` prefix
- 📖 **Documentation**: See `docs/` folder
- ❓ **Questions**: Open a discussion

---

Made with ❤️ for Azure DevOps developers

*This skill saves you ~5 minutes per PR by automating the tedious parts of PR creation!*
