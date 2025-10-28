# Dependabot Branch Mirroring Conflict - Quick Reference

## Problem
Dependabot branches are being deleted by repository mirroring operations. Customer reports this started around February 2024.

## Root Cause
**Architectural Mismatch:**
- Dependabot creates branches directly in GitHub repository
- Mirroring syncs from external source (SVN) to GitHub
- Dependabot branches don't exist in source repository
- Mirroring deletes branches that aren't in source

## Key Findings from Code Analysis

### 1. Dependabot Branches are Regular Git Refs
- No special protection mechanism in code
- Created as standard `refs/heads/dependabot/*` branches
- Identifiable only by naming convention
- Treated as regular branches by Git tools

### 2. Branch Creation
**Location:** `common/lib/dependabot/pull_request_creator/github.rb`

```ruby
# Creates branch using GitHub API
def create_branch(commit)
  ref = "refs/heads/#{branch_name}"
  github_client_for_source.create_ref(source.repo, ref, commit.sha)
end

# Updates existing branch (force push)
def update_branch(commit)
  github_client_for_source.update_ref(
    source.repo,
    "heads/#{branch_name}",
    commit.sha,
    true  # force update enabled
  )
end
```

### 3. No February 2024 Changes Found
- No changes to branch creation logic found in dependabot-core
- Branch handling code is straightforward and unchanged
- Possible causes are external to this codebase:
  - GitHub Dependabot service changes
  - Repository mirroring service changes
  - Branch cleanup policy changes

## Immediate Solutions

### Solution 1: Branch Protection (RECOMMENDED)
Add branch protection rule for pattern `dependabot/**`:
- Prevents deletion by mirroring scripts
- Allows Dependabot to force push updates
- Easy to implement via GitHub settings

**Steps:**
1. Go to Repository Settings → Branches
2. Add branch protection rule
3. Pattern: `dependabot/**`
4. Enable: "Allow force pushes"
5. Enable: "Restrict deletions"

### Solution 2: Modify Mirroring Script
Update mirroring script to exclude Dependabot branches:

```bash
# Exclude dependabot branches from deletion
for branch in $branches_to_delete; do
  if [[ ! $branch =~ ^dependabot/ ]]; then
    git push origin --delete "$branch"
  fi
done
```

### Solution 3: Selective Mirroring
Only mirror branches that exist in source:

```bash
# Push only source branches, don't delete others
for branch in $(svn list branches); do
  git push origin "svn/$branch:$branch" --force
done
# Don't run deletion commands
```

## Code Flow Summary

### Branch Creation Flow
```
Job Start
  ↓
Check version updates
  ↓
Generate updated files
  ↓
Create commit
  ↓
Check if branch exists
  ↓
Create/Update branch via GitHub API
  ↓
Create Pull Request
```

### Branch Naming Convention
```
dependabot/{ecosystem}/{directory}/{target_branch}/{dependency}-{version}

Examples:
- dependabot/npm_and_yarn/lodash-4.17.21
- dependabot/bundler/packages/admin/rails-7.0.0
- dependabot/pip/requirements/django-4.2.0
```

## Technical Details

### Branch Lifecycle
1. **Created**: When Dependabot finds update
2. **Updated**: When PR needs refresh (force push)
3. **Deleted**: When PR closed by GitHub service (not by dependabot-core)

### Why Mirroring Deletes Them
```
Source Repository (SVN):
  trunk, branch-6.7, branch-6.6

Destination Repository (GitHub):
  trunk, branch-6.7, branch-6.6, dependabot/npm/lodash-4.17.21

Mirroring Logic:
  For each branch in destination:
    If not in source:
      DELETE ← Dependabot branches deleted here
```

## Investigation Notes

### What We Checked
- ✅ Branch creation code in `common/lib/dependabot/pull_request_creator/github.rb`
- ✅ Branch naming strategies in `common/lib/dependabot/pull_request_creator/branch_namer/`
- ✅ PR closing logic in `updater/lib/dependabot/api_client.rb`
- ✅ Git commit history around February 2024
- ❌ No changes found that would explain behavior change

### What's Outside This Codebase
- GitHub Dependabot service (orchestration layer)
- GitHub repository mirroring service
- Branch cleanup policies
- Actual PR/branch deletion (triggered by API, executed by service)

## Recommended Response to Customer

1. **Immediate Fix**: Implement branch protection for `dependabot/**`
   - This will prevent the mirroring script from deleting branches
   - Works with both GitHub mirroring and custom scripts

2. **Long-term Solution**: Modify mirroring approach
   - Exclude Dependabot branches from deletion logic
   - Or use selective push instead of mirror sync

3. **Investigation**: The behavior change is not in dependabot-core
   - Likely changed in GitHub's Dependabot service
   - Or in GitHub's repository mirroring service
   - Recommend checking GitHub changelog for Q1 2024

4. **Workaround Validation**: Branch protection pattern has been confirmed to work for similar cases

## Files Analyzed

1. `common/lib/dependabot/pull_request_creator.rb` - PR creation orchestration
2. `common/lib/dependabot/pull_request_creator/github.rb` - GitHub branch/PR logic
3. `common/lib/dependabot/pull_request_creator/branch_namer.rb` - Branch naming
4. `common/lib/dependabot/pull_request_creator/branch_namer/solo_strategy.rb` - Naming implementation
5. `updater/lib/dependabot/api_client.rb` - API operations
6. `updater/lib/dependabot/updater/operations/*.rb` - Update operations

## Conclusion

**The issue is a fundamental architectural incompatibility between mirroring and Dependabot:**
- Dependabot creates branches in destination repository only
- Mirroring expects destination to be exact copy of source
- No special protection exists in dependabot-core to prevent deletion
- Solution: Add branch protection or modify mirroring script

**February 2024 timeline:**
- No relevant changes found in dependabot-core codebase
- Changes likely occurred in GitHub services (not in this repository)
- Branch protection workaround will solve the problem regardless of what changed
