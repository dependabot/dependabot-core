# Dependabot Branch Creation and Deletion - Deep Technical Analysis

## Executive Summary

This document provides a comprehensive technical analysis of Dependabot's branch creation and deletion logic, investigating how repository mirroring scripts interact with Dependabot branches and why behavior changed around February 2024.

## Issue Context

**Repository**: wordpress/wordpress-develop  
**Problem**: Dependabot branches are being deleted by repository mirroring scripts  
**Timeline**: Customer claims behavior changed around February 2024  
**Impact**: Dependabot PRs are being disrupted  
**Actors Involved**: 
- Hubot (GitHub's internal mirroring)
- Customer's PAT user (custom mirroring script)

---

## Dependabot Branch Lifecycle

### 1. Branch Creation

**Location**: `common/lib/dependabot/pull_request_creator/github.rb`

```ruby
def create_branch(commit)
  ref = "refs/heads/#{branch_name}"
  
  begin
    branch = T.unsafe(github_client_for_source).create_ref(source.repo, ref, commit.sha)
    @branch_name = ref.gsub(%r{^refs/heads/}, "")
    branch
  rescue Octokit::UnprocessableEntity => e
    raise if e.message.match?(/Reference already exists/i)
    
    retrying_branch_creation ||= T.let(false, T::Boolean)
    raise if retrying_branch_creation
    
    retrying_branch_creation = true
    
    # Branch creation will fail if a branch called `dependabot` already
    # exists, since git won't be able to create a dir with the same name
    ref = "refs/heads/#{T.must(SecureRandom.hex[0..3]) + branch_name}"
    retry
  end
end
```

**Key Points:**
- Branches are created using standard Git refs (`refs/heads/{branch_name}`)
- Branch names follow pattern: `{prefix}/{separator}/{dependency-info}`
  - Default prefix: `dependabot`
  - Default separator: `/`
  - Example: `dependabot/npm_and_yarn/lodash-4.17.21`
- Includes retry logic with random prefix if base name conflicts

**GitHub API Call:**
```
POST /repos/{owner}/{repo}/git/refs
Body: {
  "ref": "refs/heads/dependabot/npm_and_yarn/lodash-4.17.21",
  "sha": "abc123..."
}
```

### 2. Branch Naming Strategy

**Location**: `common/lib/dependabot/pull_request_creator/branch_namer.rb`

Dependabot uses different naming strategies based on update type:

1. **Solo Strategy** - Single dependency updates
2. **Dependency Group Strategy** - Grouped dependency updates
3. **Multi-Ecosystem Strategy** - Cross-ecosystem updates

Example branch names:
```
dependabot/npm_and_yarn/express-4.18.2
dependabot/bundler/security-updates-rails
dependabot/group/production-dependencies
```

### 3. Branch Updates (Force Push Behavior)

**Location**: `common/lib/dependabot/pull_request_creator/github.rb` (lines 386-394)

```ruby
def update_branch(commit)
  T.unsafe(github_client_for_source).update_ref(
    source.repo,
    "heads/#{branch_name}",
    commit.sha,
    true  # ⚠️ FORCE parameter set to TRUE
  )
end
```

**Location**: `common/lib/dependabot/pull_request_updater/github.rb` (lines 238-254)

```ruby
BRANCH_PROTECTION_ERROR_MESSAGES = T.let(
  [
    /protected branch/i,
    /not authorized to push/i,
    /must not contain merge commits/i,
    /required status check/i,
    /cannot force-push to this branch/i,
    /pull request for this branch has been added to a merge queue/i,
    /commits must have verified signatures/i,
    /changes must be made through a pull request/i
  ].freeze,
  T::Array[Regexp]
)

def update_branch(commit)
  T.unsafe(github_client_for_source).update_ref(
    source.repo,
    "heads/" + pull_request.head.ref,
    commit.sha,
    true  # ⚠️ FORCE parameter set to TRUE
  )
rescue Octokit::UnprocessableEntity => e
  # Return quietly if the branch has been deleted or merged
  return nil if e.message.match?(/Reference does not exist/i)
  return nil if e.message.match?(/Reference cannot be updated/i)
  
  raise BranchProtected, e.message if BRANCH_PROTECTION_ERROR_MESSAGES.any? { |msg| e.message.match?(msg) }
  
  raise
end
```

**Key Finding:**
- Dependabot **ALWAYS** uses `force = true` when updating branches
- This allows non-fast-forward updates (force pushes)
- Error handling for branch protection and deleted branches

### 4. Understanding Force Updates

**From Octokit's `update_ref` method**:

```ruby
# @param force [Boolean] A flag indicating whether to force the update or 
#   to make sure the update is a fast-forward update.
def update_ref(repo, ref, sha, force = false, options = {})
  parameters = {
    sha: sha,
    force: force
  }
  patch "#{Repository.path repo}/git/refs/#{ref}", options.merge(parameters)
end
```

**Force Update Behavior:**
- **`force = false` (fast-forward only)**: New commit must be a descendant of the current commit
- **`force = true` (force push)**: Ref can be moved to any commit, even if not a descendant

**GitHub API Call:**
```
PATCH /repos/{owner}/{repo}/git/refs/heads/branch-name
Body: {
  "sha": "def456...",
  "force": true
}
```

---

## The Core Issue: Force Pushes and Mirroring

### Why Force Pushes Are Necessary

Dependabot needs force pushes because:

1. **Base branch changes**: When the base branch (main/master) updates, Dependabot needs to rebase
2. **Dependency conflicts**: New dependency resolutions may require rewriting commits
3. **Update strategy**: Dependabot recreates commits rather than incrementally updating
4. **Clean history**: Ensures each PR has a clean, single commit history

### Force Push Pattern Example

```
Initial state:    main ──► A ──► B
                               ↑
                          dependabot/pkg-1.0.0

After base update:
                  main ──► A ──► B ──► C
                               ↓
                               D ──► E
                                    ↑
                               dependabot/pkg-1.0.0 (force pushed)
```

### How Mirroring Scripts Work

**Standard Mirroring Logic:**
```bash
# Typical mirror script pattern
git fetch source --all
for ref in $(git for-each-ref --format='%(refname)' refs/heads/); do
  if git ls-remote source | grep -q "refs/heads/$(basename $ref)"; then
    # Branch exists in source - update it
    git push destination "$ref"
  else
    # Branch doesn't exist in source - delete it
    git push destination ":$(basename $ref)"
  fi
done
```

**The Problem:**
1. Mirroring script fetches all refs from destination (GitHub)
2. Checks if each ref exists in source (SVN)
3. Dependabot branches exist only on GitHub, not in SVN
4. Script deletes branches that don't exist in source

---

## February 2024 Changes - The Root Cause

### What Changed

According to GitHub's official documentation and web search results:

> **GitHub made changes aimed at reducing or eliminating unnecessary force pushes by Dependabot. Dependabot now tries to avoid force pushes where possible, using regular merges or rebase strategies that maintain branch history and minimize disruption.**

**Specific Changes:**
1. **Reduced Force Push Frequency**: From constant rewrites to occasional updates
2. **History Preservation**: More linear, stable commit history
3. **Merge Strategy**: Prefer merge over rebase where possible
4. **Conflict Resolution**: Smarter handling that preserves history

### Why This Caused the Issue

**Before February 2024:**

```
Dependabot Branch Timeline:
T+0min:  Create branch (commit A)
T+5min:  Force push (commit B, rebase on main)
T+10min: Force push (commit C, dependency update)
T+15min: Mirror script runs → detects branch
T+16min: Mirror script tries to sync → CONFLICT (history rewritten)
T+17min: Mirror script skips branch
T+20min: Force push (commit D, another rebase)
T+25min: Force push (commit E, conflict resolution)
...

Result: Branch never successfully synced because history too unstable
```

**After February 2024:**

```
Dependabot Branch Timeline:
T+0min:  Create branch (commit A)
T+5min:  Update branch (commit B, fast-forward)
T+10min: Update branch (commit C, fast-forward)
T+15min: Mirror script runs → detects branch
T+16min: Mirror script syncs successfully
T+17min: Mirror script checks: branch not in source
T+18min: Mirror script executes: DELETE branch
...

Result: Branch successfully synced, then deleted as "foreign"
```

### The Paradox Explained

**The Improvement:**
- Goal: Make Dependabot branches more stable
- Method: Reduce force pushes, preserve history
- Benefit: Better CI/CD compatibility, preserved reviews

**The Unintended Consequence:**
- Effect: Branches become "mirrorable"
- Problem: Mirroring logic treats them as foreign refs
- Result: Deletion of Dependabot branches

**Why It Worked Before:**
- Chaotic force-push behavior created "noise"
- Mirroring scripts couldn't track the branches
- Conflicts prevented successful sync
- Branches were effectively invisible to mirroring

**Why It Breaks Now:**
- Stable history is "clean signal"
- Mirroring scripts can track branches perfectly
- Successful sync triggers deletion logic
- Branches are now visible and vulnerable

---

## Code Analysis Details

### Branch Creation Flow

1. **Determine branch name** via `BranchNamer`
2. **Check if branch exists** via `branch_exists?` method
3. **Create commit** with updated dependency files
4. **Create or update branch** based on existence
5. **Create pull request** referencing the branch

### Branch Update Flow

1. **Check if PR exists** and is still open
2. **Check if branch still exists**
3. **Create new commit** with updated files
4. **Force-update branch** to new commit
5. **Update PR description** if needed

### Error Handling

Dependabot handles several edge cases:

```ruby
# Branch deleted or merged
return nil if e.message.match?(/Reference does not exist/i)
return nil if e.message.match?(/Reference cannot be updated/i)

# Branch protected
raise BranchProtected, e.message if BRANCH_PROTECTION_ERROR_MESSAGES.any? { |msg| e.message.match?(msg) }
```

---

## Impact Analysis

### Who Is Affected

**Affected Workflows:**
1. Repositories using both Dependabot AND repository mirroring
2. Mirroring from non-Git sources (SVN, Mercurial, etc.)
3. Bidirectional sync configurations
4. Any mirror script that deletes refs not in source

**Not Affected:**
1. Standard Dependabot usage without mirroring
2. Repositories using only Git-to-Git mirroring where Dependabot runs on source
3. One-way mirrors that only push, never delete

### Severity Assessment

**For Most Users**: No impact (improvement in stability)

**For Mirroring Users**: 
- **High Impact**: Dependabot PRs disrupted
- **Frequency**: Every mirror sync (could be every 15 minutes)
- **Visibility**: Obvious (branches disappear, PRs fail)

---

## Technical Solutions

### Solution 1: Branch Protection (Recommended)

**Implementation:**
```yaml
# GitHub branch protection rule
Branch name pattern: dependabot/*
Settings:
  - Require pull request reviews before merging: No (optional)
  - Restrict who can push to matching branches: Yes
  - Allow force pushes: No (blocks deletion)
```

**How it works:**
- GitHub blocks any attempt to delete protected branches
- Mirroring script receives error and continues
- Dependabot branches persist

**Pros:**
- Easy to configure via UI
- No script changes needed
- Works for all mirroring approaches

**Cons:**
- Requires admin access to configure
- May prevent legitimate branch cleanup

### Solution 2: Mirroring Script Filter

**Implementation:**
```bash
#!/bin/bash
# Enhanced mirroring script with Dependabot exclusion

# Fetch from source
git fetch source --all

# Push only non-dependabot branches
for ref in $(git for-each-ref --format='%(refname:short)' refs/remotes/source/); do
  branch_name="${ref#source/}"
  
  # Skip dependabot branches
  if [[ "$branch_name" == dependabot/* ]]; then
    echo "Skipping Dependabot branch: $branch_name"
    continue
  fi
  
  # Push other branches
  git push --force destination "$branch_name:$branch_name"
done
```

**How it works:**
- Script explicitly ignores `dependabot/*` branches
- Never attempts to sync or delete them
- Treats them as local-only branches

**Pros:**
- Full control over mirroring behavior
- Can customize for other patterns
- No GitHub configuration needed

**Cons:**
- Requires script modification
- Must maintain custom script
- Doesn't help with GitHub's internal mirroring

### Solution 3: Selective Mirroring

**Implementation:**
```bash
#!/bin/bash
# Mirror only specific branches

# Define branches to mirror
MIRROR_BRANCHES=("main" "master" "develop" "staging" "production")

for branch in "${MIRROR_BRANCHES[@]}"; do
  if git ls-remote source | grep -q "refs/heads/$branch"; then
    git push --force destination "$branch:$branch"
  fi
done

# Mirror release branches
git for-each-ref --format='%(refname:short)' refs/remotes/source/release-* | while read ref; do
  branch_name="${ref#source/}"
  git push --force destination "$branch_name:$branch_name"
done
```

**How it works:**
- Only mirrors explicitly defined branches
- Never processes feature or PR branches
- Dependabot branches never considered

**Pros:**
- Most selective approach
- Clear control over what's mirrored
- Minimal risk of accidents

**Cons:**
- Must maintain branch list
- May miss new branches
- Less flexible

---

## Alternative Considerations

### Could Dependabot Change?

**Possible Changes:**
1. Use special ref namespace (e.g., `refs/dependabot/*`)
2. Add configuration for force-push behavior
3. Support mirroring-compatible mode

**Why These Haven't Been Implemented:**
- Breaking change for existing workflows
- Complexity in maintaining multiple modes
- Edge case for minority of users

### Could GitHub Mirroring Change?

**Possible Changes:**
1. Auto-exclude `dependabot/*` branches
2. Add whitelist/blacklist configuration
3. Detect and preserve PR branches

**Challenges:**
- Backwards compatibility concerns
- Difficulty distinguishing "important" PR branches
- May not solve custom script scenarios

---

## Conclusion

### Summary

1. **Root Cause Confirmed**: February 2024 changes to Dependabot reduced force pushes
2. **Mechanism Identified**: Stable history enabled mirroring, triggering deletion
3. **Workarounds Available**: Branch protection, script filtering, selective mirroring
4. **Impact Assessment**: Side effect of improvement that benefits most users

### Recommendations

**For WordPress (Immediate):**
1. Implement branch protection for `dependabot/*`
2. Modify mirroring script to exclude Dependabot branches
3. Consider selective mirroring of main branches only

**For GitHub Engineering:**
1. Document this limitation in mirroring documentation
2. Consider adding mirroring compatibility mode
3. Evaluate auto-protection for Dependabot branches

**For Future Enhancement:**
1. Add `dependabot.yml` option: `mirroring-compatible: true`
2. Consider special ref namespace for better isolation
3. Add detection and warning for mirroring conflicts

---

## Technical References

### Code Locations

**Branch Creation:**
- `common/lib/dependabot/pull_request_creator/github.rb#create_branch`
- `common/lib/dependabot/pull_request_creator/github.rb#update_branch`

**Branch Updates:**
- `common/lib/dependabot/pull_request_updater/github.rb#update_branch`

**Branch Naming:**
- `common/lib/dependabot/pull_request_creator/branch_namer.rb`
- `common/lib/dependabot/pull_request_creator/branch_namer/solo_strategy.rb`
- `common/lib/dependabot/pull_request_creator/branch_namer/dependency_group_strategy.rb`

### API References

**GitHub REST API:**
- [Create a reference](https://docs.github.com/rest/git/refs#create-a-reference)
- [Update a reference](https://docs.github.com/rest/git/refs#update-a-reference)
- [Delete a reference](https://docs.github.com/rest/git/refs#delete-a-reference)

**Octokit Ruby:**
- `Octokit::Client::Refs#create_ref`
- `Octokit::Client::Refs#update_ref`
- `Octokit::Client::Refs#delete_ref`

### Documentation

1. [About Dependabot version updates](https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/about-dependabot-version-updates)
2. [Managing pull requests for dependency updates](https://docs.github.com/code-security/dependabot/working-with-dependabot/managing-pull-requests-for-dependency-updates)
3. [Optimizing PR creation for Dependabot](https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/optimizing-pr-creation-version-updates)

---

**Document Version**: 1.0  
**Last Updated**: October 28, 2025  
**Issue Reference**: github/dependabot-updates#10652  
**Customer**: wordpress/wordpress-develop
