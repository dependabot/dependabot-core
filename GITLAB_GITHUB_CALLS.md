# Using Dependabot Core on GitLab: GitHub API Calls Analysis

## Executive Summary

**Yes, you can use Dependabot Core on GitLab without making calls to GitHub for your main repository operations.** However, Dependabot may still make calls to GitHub to fetch metadata about dependencies that are hosted on GitHub.

## Overview

Dependabot Core is designed to work with multiple Git hosting platforms including GitLab, GitHub, Bitbucket, Azure DevOps, and AWS CodeCommit. The codebase has provider-agnostic abstractions that route operations to the appropriate platform client.

## When GitHub API Calls Are Made

### 1. **Your Repository is on GitLab → No GitHub Calls for Repository Operations**

When your source repository is on GitLab, Dependabot uses the GitLab API exclusively for:
- ✅ Fetching dependency files from your repository
- ✅ Creating merge requests
- ✅ Updating merge requests
- ✅ Creating branches and commits
- ✅ Adding reviewers and assignees
- ✅ Adding labels and milestones

**Implementation:** `common/lib/dependabot/clients/gitlab_with_retries.rb` and related GitLab-specific classes.

### 2. **Dependencies Hosted on GitHub → GitHub Calls for Metadata**

Dependabot **may** make calls to GitHub when your dependencies themselves are hosted on GitHub, regardless of where your repository is hosted. This happens when enriching merge request descriptions with:

- **Changelogs**: Fetching CHANGELOG.md files from GitHub repositories
- **Release Notes**: Fetching GitHub Releases information
- **Commit History**: Fetching commit messages between versions
- **Maintainer Info**: Fetching maintainer details from GitHub profiles

**Example Scenario:**
```
Your Repository: gitlab.com/your-org/your-project
Dependency: github.com/rails/rails (Ruby gem)

→ GitLab API: Used for your repository operations
→ GitHub API: Used to fetch changelog from github.com/rails/rails
```

## What Data Is Sent to GitHub

When Dependabot makes calls to GitHub (for dependency metadata), it sends:

### Read-Only API Calls
All GitHub API calls related to dependency metadata are **read-only**. No data from your repository is sent to GitHub.

**Requests Made:**
- `GET /repos/{owner}/{repo}/contents/{path}` - Fetch changelog files
- `GET /repos/{owner}/{repo}/releases` - Fetch release information  
- `GET /repos/{owner}/{repo}/commits` - Fetch commit history
- `GET /repos/{owner}/{repo}/compare/{base}...{head}` - Compare versions

**Query Parameters:**
- Repository owner/name (of the dependency)
- File paths (e.g., "CHANGELOG.md")
- Git references (tags, commits)
- Pagination parameters

**Headers:**
- `Authorization: token <github-token>` (if provided for rate limiting)
- `User-Agent: Dependabot-Core/...`
- `Accept: application/vnd.github.v3+json`

### Data NOT Sent to GitHub

When your repository is on GitLab:
- ❌ Your source code
- ❌ Your dependency files (package.json, Gemfile, etc.)
- ❌ Your commit messages
- ❌ Your repository structure
- ❌ Any proprietary information
- ❌ Information about your private dependencies

## Graceful Degradation

Metadata fetching from GitHub is **optional** and **non-critical**:

### Behavior When GitHub Is Unreachable

If GitHub API calls fail (network blocked, rate limited, timeout), Dependabot:
1. Catches the error
2. Logs the failure
3. **Continues creating the merge request without the metadata**

**Code Reference:** `common/lib/dependabot/pull_request_creator/message_builder.rb:147-149`
```ruby
rescue StandardError => e
  suppress_error("PR message", e)
  suffixed_pr_message_header + prefixed_pr_message_footer
end
```

**Additional Error Handling Examples:**
- `commits_finder.rb`: `rescue Octokit::NotFound then []` - Returns empty array on 404
- `release_finder.rb`: `rescue Octokit::NotFound then []` - Returns empty array on 404
- `changelog_finder.rb`: Multiple rescue blocks for graceful degradation

### Result
- ✅ Merge requests are still created
- ✅ Dependency updates still work
- ℹ️ PR descriptions have less context (no changelog, commits, or release notes)

## How to Minimize or Prevent GitHub API Calls

### Option 1: Block GitHub API Access (Recommended for High Security)

**Network-Level Blocking:**
```bash
# Block api.github.com at firewall/proxy level
# Dependabot will gracefully degrade
```

**Result:** Merge requests created successfully, but without GitHub-hosted dependency metadata.

### Option 2: Don't Provide GitHub Credentials

Don't configure GitHub credentials in Dependabot. This limits:
- GitHub API rate limits to 60 requests/hour (unauthenticated)
- May fail to fetch metadata for some dependencies due to rate limiting
- Falls back to basic PR messages

### Option 3: Use Private Registry Mirrors

For dependencies hosted on GitHub:
1. Mirror them to your own private registry (e.g., Nexus, Artifactory)
2. Configure Dependabot to use your private registry
3. The dependency metadata will come from your registry instead of GitHub

## Platform Abstraction Architecture

Dependabot uses a provider-agnostic pattern throughout the codebase:

### Pull Request Creation
**Location:** `common/lib/dependabot/pull_request_creator.rb:257-266`
```ruby
def create
  case source.provider
  when "github" then github_creator.create
  when "gitlab" then gitlab_creator.create
  when "azure" then azure_creator.create
  when "bitbucket" then bitbucket_creator.create
  when "codecommit" then codecommit_creator.create
  else raise "Unsupported provider #{source.provider}"
  end
end
```

### Metadata Fetching
**Location:** `common/lib/dependabot/metadata_finders/base/changelog_finder.rb:233-240`
```ruby
case file_source.provider
when "github" then fetch_github_file(file_source, file)
when "gitlab" then fetch_gitlab_file(file)
when "bitbucket" then fetch_bitbucket_file(file)
when "azure" then fetch_azure_file(file)
when "codecommit" then nil
else raise "Unsupported provider '#{file_source.provider}'"
end
```

**Key Implementation Classes:**
- `common/lib/dependabot/clients/gitlab_with_retries.rb` - GitLab API client wrapper
- `common/lib/dependabot/pull_request_creator/gitlab.rb` - GitLab merge request creator
- `common/lib/dependabot/pull_request_updater/gitlab.rb` - GitLab merge request updater
- `common/lib/dependabot/file_fetchers/base.rb` - Multi-provider file fetching
- `common/lib/dependabot/metadata_finders/base/` - Provider-aware metadata fetchers

## Configuration for GitLab

### Basic Configuration

```ruby
source = Dependabot::Source.from_url("https://gitlab.com/your-org/your-project")
# source.provider => "gitlab"

credentials = [
  {
    "type" => "git_source",
    "host" => "gitlab.com",
    "username" => "x-access-token",
    "password" => "<gitlab-personal-access-token>"
  }
]
```

### Self-Hosted GitLab

```ruby
source = Dependabot::Source.from_url("https://gitlab.your-company.com/your-org/your-project")

credentials = [
  {
    "type" => "git_source", 
    "host" => "gitlab.your-company.com",
    "username" => "x-access-token",
    "password" => "<gitlab-token>"
  }
]
```

## Recommendations

### For High-Security Environments

1. **Block api.github.com** at the network level
   - Dependabot will work correctly for GitLab repositories
   - Metadata enrichment will be skipped automatically
   - No GitHub data leakage possible

2. **Use private registries** for all dependencies
   - Mirror public packages to internal registry
   - Configure Dependabot to use private registry only
   - Eliminates need to contact external package sources

3. **Run Dependabot in isolated network**
   - Air-gapped network or DMZ
   - Only allow outbound to GitLab and private registries
   - Block all other external domains

### For Standard Environments

1. **Allow GitHub API (read-only)** for better UX
   - Provides changelog and release notes in MRs
   - Helps developers understand changes
   - No sensitive data sent to GitHub

2. **Rate limit considerations**
   - Provide GitHub token to increase rate limits (5000/hour vs 60/hour)
   - Token only used for reading public metadata
   - Can be a dedicated read-only token

## Known Issues

### GitMetadataFetcher Bug

**Location:** `common/lib/dependabot/metadata_finders/base/git_metadata_fetcher.rb:151`

The `ref_details_for_pinned_ref()` method hardcodes GitHub API URLs and doesn't support GitLab for pinned git references. This is a minor bug that affects edge cases.

**Impact:** Minimal - only affects dependencies pinned to specific git commits on GitLab.

## FAQ

### Q: Can I use Dependabot on GitLab without any GitHub access?
**A:** Yes. Your repository operations use GitLab API exclusively. GitHub calls only happen for fetching metadata about dependencies hosted on GitHub, which gracefully degrades if blocked.

### Q: What information does GitHub receive?
**A:** Only read-only API requests for public dependency metadata (changelogs, releases, commits). No information about your repository or code.

### Q: Can I completely prevent GitHub API calls?
**A:** Yes. Block api.github.com at the network level. Dependabot will continue working, just without metadata enrichment in PR descriptions.

### Q: Does Dependabot send my code to GitHub?
**A:** No. When using GitLab, no code or dependency files from your repository are sent to GitHub.

### Q: Are there any security risks?
**A:** Minimal. GitHub API calls are read-only for public data. If you block GitHub entirely, there's zero risk as no calls will be made.

### Q: Does this affect dependency updates?
**A:** No. Dependency updates work normally. Only the metadata (changelog, release notes) in merge request descriptions is affected.

## Conclusion

**Dependabot Core can safely run on GitLab with minimal to no GitHub integration:**

✅ **Repository operations** use GitLab API exclusively  
✅ **GitHub calls are read-only** for dependency metadata  
✅ **GitHub access is optional** - graceful degradation  
✅ **No sensitive data** sent to GitHub  
✅ **Network blocking supported** - MRs still created  

For maximum security, block api.github.com at the network level. Dependabot will function normally for your GitLab projects, with the only limitation being less detailed merge request descriptions.

## Additional Resources

- [Dependabot Core Repository](https://github.com/dependabot/dependabot-core)
- [GitLab Integration Code](common/lib/dependabot/clients/gitlab_with_retries.rb)
- [Metadata Finders](common/lib/dependabot/metadata_finders/)
- [Pull Request Creators](common/lib/dependabot/pull_request_creator/)

## Support

If you have additional questions or concerns, please open an issue on the [Dependabot Core repository](https://github.com/dependabot/dependabot-core/issues).
