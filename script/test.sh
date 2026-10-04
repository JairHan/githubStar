#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/githubstar-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
# Compile the production data layer directly: no XCTest or macro plugins required.
swiftc -parse-as-library Sources/GitHubStar/Support/GitHubOAuthConfiguration.swift Sources/GitHubStar/Models/Repository.swift Sources/GitHubStar/Models/GitHubAccount.swift Sources/GitHubStar/Services/TrendingParser.swift Sources/GitHubStar/Services/GitHubClient.swift Sources/GitHubStar/Services/GitHubOAuthClient.swift Tests/GitHubStarTests/*.swift -o "$TEST_DIR/DataValidation"
"$TEST_DIR/DataValidation"
