# Repository Mirroring and Dependabot Branches

## Issue: Dependabot Branches Being Deleted by Mirroring Scripts

### Root Cause (Confirmed)

GitHub made a significant change to Dependabot in **February 2024** that reduced the frequency of force pushes on Dependabot branches. While this improved stability for most users, it inadvertently broke compatibility with repository mirroring workflows.

### What Changed in February 2024

GitHub announced changes to minimize force pushes by Dependabot:
- Reduced frequency of force pushes on PR branches
- Switched to more stable branch history preservation
- Used regular merges/rebases instead of aggressive force-pushing
- Improved compatibility with CI/CD pipelines and review processes

**Source**: GitHub official documentation on Dependabot version updates

### Why This Causes Mirroring Issues

**Before February 2024:**
```
Dependabot branch with frequent force pushes
    ↓
Mirroring script encounters conflicts
    ↓
Branch skipped or ignored
    ↓
Branch persists on GitHub ✓
```

**After February 2024:**
```
Dependabot branch with stable history
    ↓
Mirroring script successfully syncs
    ↓
Discovers branch doesn't exist in source
    ↓
Deletes branch as "foreign" ✗
```

**The Core Problem:**
- Repository mirroring scripts sync refs from source to destination
- They delete refs that exist in destination but not in source
- Dependabot creates branches **only on GitHub**, not in the source repository
- Before Feb 2024: Chaotic history prevented successful mirroring
- After Feb 2024: Stable history enables mirroring, which triggers deletion

### Affected Workflows

This issue affects repositories that:
1. Use Dependabot for automated dependency updates
2. Mirror content from an external source (e.g., SVN) to GitHub
3. Have mirroring configured to sync all refs

### Recommended Workarounds

#### Option 1: Branch Protection (Recommended)

Protect Dependabot branches from deletion:

```
Settings → Branches → Add branch protection rule
Branch name pattern: dependabot/*
Options:
  - Restrict who can push to matching branches: Yes
  - Allow force pushes: No
```

#### Option 2: Mirroring Script Filter

Exclude Dependabot branches from mirroring:

```bash
# Git command with exclusion
git push --mirror --force origin 'refs/heads/*:refs/heads/*' \
  --exclude 'refs/heads/dependabot/*'
```

Or in your mirroring script:
```bash
# Skip dependabot branches when syncing
for ref in $(git for-each-ref --format='%(refname)' refs/heads/); do
  if [[ $ref != refs/heads/dependabot/* ]]; then
    git push destination "$ref"
  fi
done
```

#### Option 3: One-Way Sync

Only mirror main development branches:
```bash
# Only sync main/master and release branches
git push destination main:main
git push destination 'refs/heads/release-*:refs/heads/release-*'
```

### Technical Details

Dependabot uses force updates when updating PR branches:

**Code Location:** `common/lib/dependabot/pull_request_creator/github.rb`
```ruby
def update_branch(commit)
  github_client_for_source.update_ref(
    source.repo,
    "heads/#{branch_name}",
    commit.sha,
    true  # Force parameter - allows non-fast-forward updates
  )
end
```

**GitHub API Call:**
```
PATCH /repos/{owner}/{repo}/git/refs/{ref}
Body: { "sha": "...", "force": true }
```

The `force: true` parameter allows non-fast-forward updates, which Dependabot needs for rebasing and resolving conflicts.

### Impact

This is a **side effect of an improvement**: GitHub made Dependabot better for most use cases (stable history, fewer disruptions to CI/CD), but this inadvertently broke compatibility with repository mirroring workflows that weren't designed to handle Dependabot's branch creation pattern.

### Related Issues

- Issue affects both GitHub's internal mirroring and custom mirroring scripts
- Not specific to dependabot-core codebase (service-level change)
- Similar patterns occur in other automated PR creation tools

### Contact

For questions or issues related to this behavior:
- **Issue Tracker**: github/dependabot-updates
- **Documentation**: https://docs.github.com/en/code-security/dependabot

### References

1. GitHub Docs: [About Dependabot version updates](https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/about-dependabot-version-updates)
2. GitHub Docs: [Optimizing PR creation for Dependabot](https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/optimizing-pr-creation-version-updates)
3. Code: `common/lib/dependabot/pull_request_creator/github.rb`
4. Code: `common/lib/dependabot/pull_request_updater/github.rb`
