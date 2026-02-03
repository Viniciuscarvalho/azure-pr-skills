# Changelog

All notable changes to the Azure DevOps PR Automation Skill will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-01-13

### Added

- 🎉 **Initial Release**

#### Core Features
- Interactive Work Item selection from Azure Boards
- Automatic PR creation with Work Item data
- Work Item linking via ArtifactLink API
- Smart branch management (create new or use current)
- Auto-add reviewers from `AZURE_DEVOPS_REVIEWERS` config
- Draft PR by default for review before publishing

#### Technical Features
- Modular architecture with separate lib files
- Retry logic with exponential backoff for API calls
- Comprehensive error handling with clear exit codes
- Debug mode for troubleshooting (`AZURE_DEVOPS_DEBUG=true`)

#### Testing
- 173 automated tests (unit + integration)
- Test runner script (`tests/run_tests.sh`)
- Mock-based API testing (no real API calls in tests)

#### Documentation
- Complete README with usage examples
- PAT setup guide with step-by-step instructions
- Troubleshooting guide for common issues
- Installation script for easy setup

### Exit Codes
- `0`: Success
- `1`: Configuration error
- `2`: Git repository error
- `3`: Azure DevOps API error
- `4`: User cancellation

---

## [Unreleased]

### Fixed
- Changed default API version from 7.2 to 7.1 (stable) to avoid API version issues
- Updated documentation to clarify API version requirements
- Added `AZURE_API_VERSION` environment variable for version override
- Added troubleshooting guide for API version errors

### Changed
- Default Azure DevOps API version is now 7.1 (stable) instead of 7.2
- Users who need v7.2+ features can set `AZURE_API_VERSION="7.2-preview"` explicitly

### Planned
- [ ] Support for multiple organizations
- [ ] PR templates support
- [ ] Custom field mapping
- [ ] Batch PR creation
- [ ] PR update/edit functionality

---

## Release Notes Format

### [X.Y.Z] - YYYY-MM-DD

#### Added
- New features

#### Changed
- Changes to existing functionality

#### Deprecated
- Features to be removed in future

#### Removed
- Removed features

#### Fixed
- Bug fixes

#### Security
- Security updates
