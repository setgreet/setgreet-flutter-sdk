#!/bin/bash

# Setgreet Flutter SDK Publish Script
# This script handles the publishing process for the Setgreet Flutter SDK to pub.dev

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Flutter installation
check_flutter() {
    if ! command_exists flutter; then
        log_error "Flutter is not installed or not in PATH"
        exit 1
    fi

    log_info "Checking Flutter version..."
    flutter --version
}

# Function to run tests
run_tests() {
    log_info "Running tests..."

    # Run tests in main package
    if [ -d "test" ]; then
        flutter test
        log_success "Main package tests passed"
    else
        log_info "No tests found in main package"
    fi

    # Run tests in example
    if [ -d "example" ]; then
        cd example
        flutter test
        log_success "Example tests passed"
        cd ..
    fi
}

# Function to run analysis
run_analysis() {
    log_info "Running Flutter analysis..."
    flutter analyze
    log_success "Analysis completed successfully"
}

# Function to check pubspec.yaml
check_pubspec() {
    log_info "Checking pubspec.yaml..."

    if [ ! -f "pubspec.yaml" ]; then
        log_error "pubspec.yaml not found"
        exit 1
    fi

    # Check required fields
    local name=$(grep '^name:' pubspec.yaml | sed 's/name: //')
    local version=$(grep '^version:' pubspec.yaml | sed 's/version: //')
    local description=$(grep '^description:' pubspec.yaml | sed 's/description: //')

    if [ -z "$name" ]; then
        log_error "Package name not found in pubspec.yaml"
        exit 1
    fi

    if [ -z "$version" ]; then
        log_error "Package version not found in pubspec.yaml"
        exit 1
    fi

    if [ -z "$description" ]; then
        log_error "Package description not found in pubspec.yaml"
        exit 1
    fi

    log_info "Package: $name@$version"
    log_info "Description: $description"
}

# Function to check if ready for publishing
check_publish_ready() {
    log_info "Checking if package is ready for publishing..."

    # Check if there are any uncommitted changes
    if [ -n "$(git status --porcelain)" ]; then
        log_warning "You have uncommitted changes. Please commit them before publishing."
        git status
        exit 1
    fi

    # Check if on main/master branch
    local current_branch=$(git branch --show-current)
    if [[ "$current_branch" != "main" && "$current_branch" != "master" && "$current_branch" != "develop" ]]; then
        log_warning "You are on branch '$current_branch'. Consider publishing from main/master branch."
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Function to dry run publish
dry_run_publish() {
    log_info "Running dry-run publish..."
    flutter pub publish --dry-run
    log_success "Dry-run completed successfully"
}

# Function to publish package
publish_package() {
    log_info "Publishing package to pub.dev..."
    log_warning "This will publish the package to pub.dev. Are you sure?"
    read -p "Type 'yes' to continue: " confirmation

    if [ "$confirmation" != "yes" ]; then
        log_info "Publish cancelled"
        exit 0
    fi

    flutter pub publish
    log_success "Package published successfully!"
}

# Function to create git tag
create_git_tag() {
    local version=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d '\r')

    log_info "Creating git tag v$version..."
    git tag -a "v$version" -m "Release version $version"
    git push origin "v$version"
    log_success "Git tag created and pushed"
}

# Function to show post-publish steps
show_post_publish_steps() {
    local version=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d '\r')

    log_info "Post-publish checklist:"
    echo "  1. Check package on pub.dev: https://pub.dev/packages/setgreet"
    echo "  2. Update CHANGELOG.md for next version"
    echo "  3. Consider updating example app if needed"
    echo "  4. Notify team about the new release"
    echo "  5. Update documentation if needed"
    echo ""
    log_success "Version $version published successfully!"
}

# Main function
main() {
    echo ""
    log_info "Setgreet Flutter SDK Publish Script"
    log_info "=================================="
    echo ""

    # Check if dry-run only
    DRY_RUN=false
    if [ "$1" = "--dry-run" ]; then
        DRY_RUN=true
        log_info "Running in dry-run mode"
    fi

    # Pre-publish checks
    check_flutter
    check_pubspec
    check_publish_ready

    # Quality checks
    run_analysis
    run_tests

    # Publish process
    if [ "$DRY_RUN" = true ]; then
        dry_run_publish
        log_success "Dry-run completed. Use './publish.sh' to publish for real."
    else
        dry_run_publish
        publish_package
        create_git_tag
        show_post_publish_steps
    fi
}

# Handle script arguments
case "$1" in
    --help|-h)
        echo "Usage: $0 [--dry-run]"
        echo ""
        echo "Options:"
        echo "  --dry-run    Run all checks but don't actually publish"
        echo "  --help, -h   Show this help message"
        echo ""
        echo "This script will:"
        echo "  1. Check Flutter installation"
        echo "  2. Validate pubspec.yaml"
        echo "  3. Check git status"
        echo "  4. Run flutter analyze"
        echo "  5. Run tests"
        echo "  6. Dry-run publish"
        echo "  7. Publish to pub.dev (unless --dry-run)"
        echo "  8. Create git tag"
        echo "  9. Show post-publish steps"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
