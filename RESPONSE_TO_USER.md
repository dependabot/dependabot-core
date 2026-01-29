# Response to: Using Dependabot on GitLab Without GitHub Calls

## Summary Answer

**Yes, you can use Dependabot on GitLab without making calls to GitHub for your repository operations.** However, there may be optional calls to GitHub to fetch metadata about dependencies that are hosted on GitHub.

## Key Findings

### ✅ Your Repository Operations - NO GitHub Calls

When your repository is hosted on GitLab, **ALL repository operations use GitLab API exclusively**:

- Fetching dependency files from your repository
- Creating merge requests  
- Updating merge requests
- Creating branches and commits
- Adding reviewers, assignees, labels, and milestones

**No data from your GitLab repository is ever sent to GitHub.**

### ℹ️ Dependency Metadata - Optional GitHub Calls (Read-Only)

Dependabot **may** make read-only calls to GitHub when:
1. A dependency you're updating is hosted on GitHub (e.g., Rails gem from github.com/rails/rails)
2. Fetching changelog, release notes, or commit history for that dependency
3. Enriching your merge request description with update context

**Example:**
```
Your Project:     gitlab.com/your-org/your-project  → GitLab API only
Dependency:       github.com/rails/rails            → GitHub API for metadata
```

### 🔒 What GitHub Receives (If Accessed)

**Read-only API requests for public dependency information only:**
- GET requests to fetch changelogs, releases, commits
- Repository name and version information (of the dependency, not your code)
- No information about your code, repository structure, or private data

**GitHub does NOT receive:**
- ❌ Your source code
- ❌ Your dependency files
- ❌ Your commit messages
- ❌ Your repository structure
- ❌ Any proprietary information

### 💪 Graceful Degradation

If GitHub is completely blocked:
- ✅ Merge requests still created successfully
- ✅ Dependencies still updated correctly
- ℹ️ MR descriptions have less context (no changelog/release notes)

**This is by design** - the codebase has extensive error handling to continue without metadata.

## How to Completely Prevent GitHub Calls

### Recommended: Network-Level Blocking

```bash
# Block api.github.com at your firewall/proxy
# Dependabot will work normally, just without dependency metadata enrichment
```

**Result:**
- ✅ Full functionality for GitLab repositories
- ✅ All dependency updates work
- ℹ️ Merge request descriptions are simpler (no changelogs)
- 🔒 Zero data sent to GitHub

## Architecture Evidence

Dependabot uses **provider-agnostic architecture** with clear separation:

```ruby
# From pull_request_creator.rb line 257-266
case source.provider
when "gitlab" then gitlab_creator.create  # ← Your GitLab project uses this
when "github" then github_creator.create  # ← Never called for GitLab repos
```

```ruby
# From changelog_finder.rb line 233-240  
case file_source.provider
when "gitlab" then fetch_gitlab_file(file)   # ← GitLab dependencies
when "github" then fetch_github_file(file)   # ← GitHub-hosted dependencies only
```

## Recommendations by Security Level

### High Security Environments
1. **Block api.github.com** at network level
2. Use **private package registries** for all dependencies
3. Run Dependabot in **isolated network** (only GitLab + private registries allowed)
4. Result: **Zero external calls**, complete air-gap capability

### Standard Environments  
1. **Allow GitHub API** (read-only) for better UX
2. Provides helpful changelog/release information in MRs
3. No sensitive data transmitted
4. Rate limit: Use GitHub token to avoid limits (optional)

## Additional Information

I've created a comprehensive document with:
- Detailed code references
- Configuration examples
- Security analysis
- FAQ section

**See:** `GITLAB_GITHUB_CALLS.md` in this repository

## Conclusion

**Dependabot is safe to use on GitLab with no GitHub integration concerns:**

✅ Repository operations are GitLab-only  
✅ GitHub calls (if any) are read-only for public dependency metadata  
✅ GitHub access is completely optional  
✅ Blocking GitHub has no negative impact on functionality  
✅ No proprietary or sensitive data sent to GitHub  

**For maximum security:** Simply block api.github.com at the network level. Dependabot will continue to work perfectly for your GitLab projects.
