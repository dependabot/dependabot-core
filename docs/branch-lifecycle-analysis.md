# Dependabot Branch Lifecycle Analysis

## Executive Summary

This document analyzes how Dependabot creates and manages branches for pull requests, and how this behavior might interact with repository mirroring workflows.

## Problem Statement

WordPress's `wordpress-develop` repository experienced an issue where Dependabot branches were being deleted during repository mirroring operations. The customer claims this behavior changed around February 2024, where previously Dependabot branches were somehow preserved during mirroring.

## How Dependabot Creates Branches

### Branch Naming Convention

Dependabot branches follow a predictable naming pattern defined in `common/lib/dependabot/pull_request_creator/branch_namer/`:

**Default Pattern:** `{prefix}/{package_manager}/{directory}/{target_branch}/{dependency_name}-{version}`

**Example:** `dependabot/npm_and_yarn/packages/editor/lodash-4.17.21`

Key components:
- **Prefix**: Default is `dependabot` (configurable via `branch_name_prefix`)
- **Package Manager**: e.g., `npm_and_yarn`, `bundler`, `pip`
- **Directory**: The subdirectory path where dependency files exist
- **Target Branch**: The base branch being updated (e.g., `main`, `trunk`)
- **Dependency Info**: Name and version of the updated dependency

### Branch Creation Process

Location: `common/lib/dependabot/pull_request_creator/github.rb`

1. **Check if branch exists** (lines 158-177)
   - Uses `git_metadata_fetcher.ref_names.include?(name)` to check existence
   - This queries the Git repository's refs directly

2. **Create or update branch** (lines 344-360)
   - If branch exists: Updates the branch reference to point to new commit
   - If branch doesn't exist: Creates a new branch reference
   - Uses GitHub API: `create_ref(source.repo, ref, commit.sha)`

3. **Branch reference format**
   - Created as: `refs/heads/{branch_name}`
   - Example: `refs/heads/dependabot/npm_and_yarn/lodash-4.17.21`

### Important Implementation Details

```ruby
def create_branch(commit)
  ref = "refs/heads/#{branch_name}"
  
  begin
    branch = T.unsafe(github_client_for_source).create_ref(source.repo, ref, commit.sha)
    @branch_name = ref.gsub(%r{^refs/heads/}, "")
    branch
  rescue Octokit::UnprocessableEntity => e
    # Handle conflicts if a parent directory has the same name
    raise if e.message.match?(/Reference already exists/i)
    
    retrying_branch_creation ||= false
    raise if retrying_branch_creation
    
    retrying_branch_creation = true
    
    # Add random prefix if there's a naming conflict
    ref = "refs/heads/#{SecureRandom.hex[0..3] + branch_name}"
    retry
  end
end

def update_branch(commit)
  T.unsafe(github_client_for_source).update_ref(
    source.repo,
    "heads/#{branch_name}",
    commit.sha,
    true  # force update
  )
end
```

## How Dependabot Deletes/Closes Branches

### Branch Deletion via PR Closure

Location: `updater/lib/dependabot/api_client.rb` (lines 91-109)

When a PR is closed, Dependabot uses the internal API to signal closure:

```ruby
def close_pull_request(dependency_names, reason)
  api_url = "#{base_url}/update_jobs/#{job_id}/close_pull_request"
  body = { data: { "dependency-names": dependency_names, reason: reason } }
  response = http_client.post(api_url, json: body)
end
```

**PR Closure Reasons:**
- `:dependency_removed` - Dependency no longer in manifest
- `:dependencies_changed` - PR dependencies have changed
- `:update_no_longer_possible` - Update cannot be performed
- `:up_to_date` - Dependency is already up to date
- `:dependency_group_empty` - Group has no dependencies

### When PRs are Closed (and branches potentially deleted)

Location: `updater/lib/dependabot/updater/operations/`

1. **During PR Refresh** (`refresh_version_update_pull_request.rb`)
   - When dependency is removed from manifest
   - When dependencies in the PR have changed
   - When dependency is already up to date
   - When update is no longer possible

2. **During Group Updates** (`refresh_group_update_pull_request.rb`)
   - When dependency group becomes empty
   - When target versions change (superseded by new PR)

3. **Security Updates** (`refresh_security_update_pull_request.rb`)
   - When security dependencies are removed

**Important Note:** The `close_pull_request` API call signals to the backend service (not in this codebase) to close the PR. The actual branch deletion is handled by the GitHub Dependabot service, not by dependabot-core.

## Key Characteristics of Dependabot Branches

### 1. Regular Git References

Dependabot branches are **regular Git branches** stored as `refs/heads/dependabot/*`. They have no special protection or marking that would distinguish them from user-created branches.

**Git Characteristics:**
- Stored in the same ref namespace as all other branches
- No special metadata or attributes
- Indistinguishable from manually created branches to Git tools
- Follow standard Git branch semantics

### 2. No Built-in Protection Mechanism

The code shows **no special mechanism** to protect Dependabot branches from external deletion:
- No special branch protection rules are automatically applied
- No Git attributes or tags mark them as Dependabot branches
- No hooks prevent deletion by other tools

### 3. Identification Method

Branches are identifiable only by their naming convention:
- Pattern: `dependabot/{ecosystem}/{path}/{dependency}-{version}`
- This is a **convention, not a technical protection**
- Any tool that doesn't respect this naming convention will treat them as regular branches

## Interaction with Repository Mirroring

### How Mirroring Works

Repository mirroring typically:
1. Fetches all refs from source repository
2. Compares refs in destination repository
3. Deletes refs in destination that don't exist in source
4. Creates/updates refs that exist in source

### Why Dependabot Branches Get Deleted

**Root Cause:** Dependabot branches exist only in the GitHub repository (destination), not in the external SVN repository (source).

**Mirroring Logic:**
```
Source (SVN) branches: [trunk, branch-6.7, branch-6.6]
Destination (GitHub) branches: [trunk, branch-6.7, branch-6.6, dependabot/npm/lodash-4.17.21]

Mirroring operation:
  - For each branch in destination:
    - If not in source:
      - DELETE branch  ← Dependabot branches get deleted here
```

### Why This Appears to Be a Recent Change

The issue description suggests this behavior changed around February 2024. However, based on the code analysis:

**No Changes to Branch Creation Logic:**
- The branch creation mechanism in `github.rb` is straightforward
- Branches are created as standard Git references
- No special protection mechanism was added or removed

**Possible External Changes:**
1. **GitHub Service Changes**: The Dependabot service (not this codebase) may have changed when/how it deletes closed PR branches
2. **Mirroring Frequency**: Changes to GitHub's mirroring service frequency (from "every 15 minutes" to "on-commit")
3. **Branch Cleanup Policy**: GitHub may have changed how long closed PR branches are retained
4. **Git Protocol Changes**: Updates to how GitHub handles refs during mirroring

**Note:** This repository (`dependabot-core`) only contains the logic for creating PRs and branches, not the GitHub service that manages mirroring or branch lifecycle.

## Technical Details: Branch Lifecycle

### Creation Flow

```
1. Dependabot Job Triggered
   ↓
2. Update Checker finds new version
   ↓
3. File Updater generates updated files
   ↓
4. PullRequestCreator.create()
   ↓
5. Create commit with updated files
   ↓
6. Check if branch exists
   ↓
7a. Branch doesn't exist → create_branch()
   ↓
   Create refs/heads/dependabot/{ecosystem}/...
   ↓
   GitHub API: POST /repos/:owner/:repo/git/refs
   
7b. Branch exists → update_branch()
   ↓
   Update existing branch to new commit (force push)
   ↓
   GitHub API: PATCH /repos/:owner/:repo/git/refs/heads/...
   ↓
8. Create Pull Request
   ↓
9. Add labels, reviewers, assignees
```

### Update Flow

```
1. PR Refresh Job Triggered
   ↓
2. Check if update still needed
   ↓
3a. Update needed → Update branch and PR
   
3b. Update not needed → close_pull_request()
   ↓
   POST /update_jobs/:id/close_pull_request
   ↓
   GitHub Service handles actual PR closure and branch deletion
```

### Branch Reference Structure

```
Repository refs structure:
refs/
├── heads/
│   ├── main
│   ├── trunk
│   ├── branch-6.7
│   └── dependabot/
│       ├── npm_and_yarn/
│       │   └── lodash-4.17.21
│       └── bundler/
│           └── rails-7.0.0
└── pull/
    └── 12345/
        ├── head
        └── merge
```

## Analysis of Mirroring Conflict

### The Core Issue

**Dependabot branches are ephemeral branches that exist only in the destination (GitHub) repository.**

1. **Source of Truth**: External SVN repository
2. **Destination**: GitHub repository with Dependabot enabled
3. **Conflict**: Dependabot creates branches in destination that don't exist in source
4. **Result**: Mirroring operation deletes branches that aren't in source

### Timeline Analysis

Based on the customer's claim of a February 2024 change:

**Hypothesis 1: Branch Cleanup Timing**
- Before Feb 2024: GitHub might have retained closed PR branches longer
- After Feb 2024: GitHub may clean up closed PR branches more aggressively
- Mirroring then finds branches already deleted

**Hypothesis 2: Mirroring Implementation**
- Before Feb 2024: GitHub's mirroring might have excluded certain branch patterns
- After Feb 2024: Mirroring became more comprehensive, deleting all non-source branches

**Hypothesis 3: Force Push Behavior**
- Before Feb 2024: Branch updates might not have been force pushes
- After Feb 2024: Branch updates use force push (see line 392: `true` parameter)
- Mirroring tools might treat force-pushed branches differently

### Code Evidence

The `update_branch` method uses force update:
```ruby
def update_branch(commit)
  T.unsafe(github_client_for_source).update_ref(
    source.repo,
    "heads/#{branch_name}",
    commit.sha,
    true  # ← This enables force update
  )
end
```

This means Dependabot can update branches without fast-forward, which might trigger different behavior in mirroring tools that check for ref history.

## Recommendations

### 1. Branch Protection Rules (Recommended)

Protect Dependabot branches using GitHub's branch protection:

**Manual Setup:**
```
Repository Settings → Branches → Branch protection rules
Pattern: dependabot/**
Rules:
- Allow force pushes (required for Dependabot updates)
- Restrict deletions
```

**Via GitHub API:**
```bash
curl -X PUT \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/:owner/:repo/branches/dependabot/**/protection \
  -d '{
    "required_status_checks": null,
    "enforce_admins": false,
    "required_pull_request_reviews": null,
    "restrictions": null,
    "allow_force_pushes": true,
    "allow_deletions": false
  }'
```

**Note:** Branch protection with pattern `dependabot/**` will prevent external tools (including mirroring scripts) from deleting these branches.

### 2. Modify Mirroring Script

Update the customer's mirroring script to exclude Dependabot branches:

**Git Mirroring Script Example:**
```bash
#!/bin/bash
# Exclude dependabot branches from deletion

# Get list of branches to delete
branches_to_delete=$(git branch -r | grep -v "dependabot" | ...)

# Only delete non-dependabot branches
for branch in $branches_to_delete; do
  if [[ ! $branch =~ ^dependabot/ ]]; then
    git push origin --delete "$branch"
  fi
done
```

**SVN to Git Mirroring:**
```python
# When syncing branches from SVN to Git
def should_delete_branch(branch_name):
    # Preserve Dependabot branches
    if branch_name.startswith('dependabot/'):
        return False
    
    # Delete other branches not in SVN source
    return branch_name not in svn_branches
```

### 3. Alternative Mirroring Strategy

Instead of full mirror sync, use selective push:

```bash
# Only push branches that exist in source
for branch in $(svn list branches); do
  git push origin "svn/$branch:$branch" --force
done

# Don't delete any branches - let GitHub manage Dependabot branches
```

### 4. Adjust Dependabot Configuration

If the repository has a complex structure, consider:

**Option A: Consolidate dependency files**
- Reduces number of Dependabot branches
- Fewer branches at risk during mirroring

**Option B: Use dependency groups**
- Groups related updates into single PRs
- Fewer branches to manage

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    groups:
      production-dependencies:
        patterns:
          - "*"
```

### 5. Investigation Steps

To determine what changed in February 2024:

1. **Check GitHub Changelog**: Review GitHub's official changelog for Dependabot changes in Q1 2024
2. **Review Audit Logs**: Examine GitHub audit logs for branch deletion events
3. **Compare Branch Histories**: Look at branch lifecycle before/after February 2024
4. **Monitor Mirroring Logs**: Add logging to identify exactly when branches are deleted

## Conclusion

### Summary of Findings

1. **Dependabot branches are regular Git branches** with no special protection mechanism in the core codebase
2. **Branches are identified only by naming convention** (`dependabot/*`)
3. **No built-in protection** exists against external deletion by mirroring tools
4. **Branch deletion happens via API call** to GitHub's service (not in this codebase)
5. **Mirroring inherently conflicts** with Dependabot's workflow because branches exist only in destination

### Root Cause

The issue is a **fundamental architectural mismatch**:
- **Mirroring expects**: Destination is a mirror of source (no extra refs)
- **Dependabot creates**: Additional branches in destination that aren't in source
- **Result**: Mirroring tools delete the "extra" Dependabot branches

### Why February 2024 Might Matter

While we found **no changes to branch creation logic** in the dependabot-core codebase, the behavior change could be due to:

1. Changes in GitHub's Dependabot service (not in this repository)
2. Changes to GitHub's repository mirroring service
3. Changes to branch cleanup policies
4. Changes to how refs are handled during mirroring operations

### Recommended Solution

**Best approach**: Implement branch protection rules for `dependabot/**` pattern
- Prevents accidental deletion by mirroring
- Allows Dependabot to continue updating branches
- Minimal configuration required
- Works with existing workflows

**Alternative**: Modify mirroring script to explicitly exclude Dependabot branches

## Further Investigation Needed

To fully resolve the "February 2024 change" question, investigation is needed in:

1. **GitHub Dependabot Service**: The service layer that orchestrates jobs (not in this repo)
2. **GitHub Repository Mirroring**: The service that handles SVN→Git mirroring
3. **GitHub Platform Changes**: Any changes to branch handling or ref management

The code in `dependabot-core` shows no changes around February 2024 that would explain the behavior change described by the customer.

## References

### Code Locations

- Branch Creation: `common/lib/dependabot/pull_request_creator/github.rb` (lines 363-394)
- Branch Naming: `common/lib/dependabot/pull_request_creator/branch_namer/` directory
- PR Closing: `updater/lib/dependabot/api_client.rb` (lines 91-109)
- Update Operations: `updater/lib/dependabot/updater/operations/` directory

### Key Files Analyzed

1. `common/lib/dependabot/pull_request_creator.rb` - Main PR creation orchestration
2. `common/lib/dependabot/pull_request_creator/github.rb` - GitHub-specific branch/PR logic
3. `common/lib/dependabot/pull_request_creator/branch_namer.rb` - Branch naming strategies
4. `updater/lib/dependabot/api_client.rb` - API client for PR operations
5. `updater/lib/dependabot/updater/operations/*.rb` - Update operation implementations

### Documentation

- Repository Mirroring: https://docs.github.com/en/repositories/creating-and-managing-repositories/duplicating-a-repository
- Branch Protection: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches
- Dependabot Configuration: https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file
