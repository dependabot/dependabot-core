# Dependabot Branch Mirroring - Visual Flow Diagrams

## Problem Overview: Why Dependabot Branches Get Deleted

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Source Repository (SVN)                               │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Branches:                                                       │   │
│  │  • trunk                                                         │   │
│  │  • branch-6.7                                                    │   │
│  │  • branch-6.6                                                    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Mirroring Operation
                                    │ (Syncs every 15 min or on-commit)
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│              Destination Repository (GitHub)                             │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Branches:                                                       │   │
│  │  • trunk                    ← From source (preserved)            │   │
│  │  • branch-6.7               ← From source (preserved)            │   │
│  │  • branch-6.6               ← From source (preserved)            │   │
│  │  • dependabot/npm/lodash-4.17.21  ← Created by Dependabot       │   │
│  │                                      ❌ DELETED by mirroring     │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↑
                                    │
                    ┌───────────────┴───────────────┐
                    │   Dependabot Service          │
                    │   Creates PR branches         │
                    │   directly on GitHub          │
                    └───────────────────────────────┘
```

## Normal Dependabot Workflow (Without Mirroring)

```
Step 1: Check for Updates
┌──────────────────────────────────────────────────────────────┐
│  Dependabot Updater                                          │
│  • Reads package.json / Gemfile / requirements.txt           │
│  • Checks for new versions in package registries            │
│  • Finds: lodash 4.17.20 → 4.17.21                          │
└──────────────────────────────────────────────────────────────┘
                            ↓
Step 2: Create Updated Files
┌──────────────────────────────────────────────────────────────┐
│  File Updater                                                │
│  • Updates package.json with new version                     │
│  • Updates lockfile (package-lock.json)                      │
│  • Creates commit with changes                               │
└──────────────────────────────────────────────────────────────┘
                            ↓
Step 3: Create Branch
┌──────────────────────────────────────────────────────────────┐
│  Pull Request Creator                                        │
│  • Generates branch name: dependabot/npm_and_yarn/lodash-... │
│  • Creates branch via GitHub API                             │
│  • Pushes commit to new branch                               │
└──────────────────────────────────────────────────────────────┘
                            ↓
Step 4: Create Pull Request
┌──────────────────────────────────────────────────────────────┐
│  GitHub Pull Request                                         │
│  • PR #123: Bump lodash from 4.17.20 to 4.17.21            │
│  • Head: dependabot/npm_and_yarn/lodash-4.17.21            │
│  • Base: trunk                                               │
│  • Status: ✅ Open                                           │
└──────────────────────────────────────────────────────────────┘
```

## With Mirroring: The Conflict

```
Timeline: Dependabot vs Mirroring

T=0: Dependabot creates branch
┌─────────────────────────────────────────────────────────────┐
│  GitHub Repository                                          │
│  • trunk                                                    │
│  • branch-6.7                                               │
│  • dependabot/npm_and_yarn/lodash-4.17.21  ✅ Created      │
│                                                             │
│  PR #123: ✅ Open                                           │
└─────────────────────────────────────────────────────────────┘

T=15min: Mirroring runs
┌─────────────────────────────────────────────────────────────┐
│  Mirroring Process                                          │
│  1. Fetch from SVN:                                         │
│     - trunk, branch-6.7, branch-6.6                        │
│  2. Compare with GitHub branches                            │
│  3. Find extra branch: dependabot/npm_and_yarn/lodash...   │
│  4. Delete extra branch ❌                                  │
└─────────────────────────────────────────────────────────────┘
                            ↓
T=15min+1sec: After mirroring
┌─────────────────────────────────────────────────────────────┐
│  GitHub Repository                                          │
│  • trunk                                                    │
│  • branch-6.7                                               │
│  • dependabot/npm_and_yarn/lodash-4.17.21  ❌ DELETED      │
│                                                             │
│  PR #123: ❌ Broken (head branch deleted)                  │
└─────────────────────────────────────────────────────────────┘
```

## Solution 1: Branch Protection

```
Repository Settings → Branch Protection Rule
┌─────────────────────────────────────────────────────────────┐
│  Pattern: dependabot/**                                     │
│                                                             │
│  Settings:                                                  │
│  ☑ Allow force pushes (needed for Dependabot updates)     │
│  ☑ Restrict deletions                                      │
│  ☐ Require pull request reviews                            │
│  ☐ Require status checks                                   │
└─────────────────────────────────────────────────────────────┘
                            ↓
Effect: Mirroring cannot delete protected branches
┌─────────────────────────────────────────────────────────────┐
│  Mirroring Process                                          │
│  1. Try to delete dependabot/npm_and_yarn/lodash-4.17.21   │
│  2. GitHub API returns: 403 Forbidden                       │
│  3. Branch preserved ✅                                     │
│  4. PR remains functional ✅                                │
└─────────────────────────────────────────────────────────────┘
```

## Solution 2: Modified Mirroring Script

```
Original Mirroring Logic:
┌─────────────────────────────────────────────────────────────┐
│  for branch in $(git branch -r); do                        │
│    if [[ ! $branch in $source_branches ]]; then            │
│      git push origin --delete "$branch"  ← Deletes all     │
│    fi                                                       │
│  done                                                       │
└─────────────────────────────────────────────────────────────┘

Modified Mirroring Logic:
┌─────────────────────────────────────────────────────────────┐
│  for branch in $(git branch -r); do                        │
│    # Skip Dependabot branches                              │
│    if [[ $branch =~ ^dependabot/ ]]; then                 │
│      continue  ← Skip deletion                             │
│    fi                                                       │
│                                                             │
│    if [[ ! $branch in $source_branches ]]; then            │
│      git push origin --delete "$branch"                    │
│    fi                                                       │
│  done                                                       │
└─────────────────────────────────────────────────────────────┘
```

## Branch Reference Structure

```
Git Repository Internal Structure:

.git/refs/
├── heads/                         ← Local branches
│   ├── trunk
│   ├── branch-6.7
│   └── dependabot/
│       └── npm_and_yarn/
│           └── lodash-4.17.21
├── remotes/                       ← Remote branches
│   └── origin/
│       ├── trunk
│       ├── branch-6.7
│       └── dependabot/
│           └── npm_and_yarn/
│               └── lodash-4.17.21
└── tags/                          ← Tags
    ├── v1.0.0
    └── v2.0.0

Important: Dependabot branches are stored in the same 
namespace as regular branches (refs/heads/). No special
protection or marking distinguishes them.
```

## Dependabot Branch Naming Pattern

```
Template:
{prefix}/{ecosystem}/{directory}/{target_branch}/{dependency}-{version}

Components:
┌─────────────────────────────────────────────────────────────┐
│ dependabot / npm_and_yarn / packages/editor / trunk /       │
│             lodash-4.17.21                                   │
│                                                              │
│ ↑           ↑              ↑                  ↑      ↑       │
│ prefix      ecosystem      directory         base   update  │
│ (config)    (auto)         (auto)            (auto) (auto)  │
└─────────────────────────────────────────────────────────────┘

Examples:
┌─────────────────────────────────────────────────────────────┐
│ Single dependency in root:                                  │
│ • dependabot/npm_and_yarn/lodash-4.17.21                   │
│                                                              │
│ With subdirectory:                                          │
│ • dependabot/bundler/packages/api/rails-7.0.0              │
│                                                              │
│ With target branch:                                         │
│ • dependabot/pip/branch-6.7/django-4.2.0                   │
│                                                              │
│ Security update:                                            │
│ • dependabot/npm_and_yarn/security/lodash-4.17.21          │
└─────────────────────────────────────────────────────────────┘
```

## Comparison: Before and After February 2024 (Hypothesis)

```
BEFORE (Hypothetical):
┌─────────────────────────────────────────────────────────────┐
│  Mirroring Process (GitHub)                                 │
│  1. Fetch from source                                       │
│  2. Update matching branches                                │
│  3. Create new branches from source                         │
│  4. Skip deletion of non-matching branches (?)              │
│     → Dependabot branches preserved                         │
└─────────────────────────────────────────────────────────────┘

AFTER (Current):
┌─────────────────────────────────────────────────────────────┐
│  Mirroring Process (GitHub)                                 │
│  1. Fetch from source                                       │
│  2. Update matching branches                                │
│  3. Create new branches from source                         │
│  4. Delete non-matching branches                            │
│     → Dependabot branches deleted ❌                        │
└─────────────────────────────────────────────────────────────┘

Note: This is speculation based on customer reports. No actual
code changes were found in dependabot-core around Feb 2024.
The change likely occurred in GitHub's mirroring service.
```

## Technical Flow: Branch Creation

```
Dependabot Core → GitHub API → Repository

1. Dependabot Core                2. GitHub API              3. Repository
┌──────────────────┐            ┌─────────────────┐        ┌──────────────┐
│ PullRequest      │   POST     │ /repos/:owner/  │        │ refs/heads/  │
│ Creator          │───────────>│ :repo/git/refs  │───────>│ dependabot/  │
│                  │            │                 │        │ ...          │
│ create_branch()  │            │ Body:           │        │              │
│ - ref: refs/...  │            │ {               │        │ Created ✅   │
│ - sha: abc123    │            │   ref: ...,     │        │              │
└──────────────────┘            │   sha: ...      │        └──────────────┘
                                │ }               │
                                └─────────────────┘

If branch exists:
┌──────────────────┐            ┌─────────────────┐        ┌──────────────┐
│ PullRequest      │   PATCH    │ /repos/:owner/  │        │ refs/heads/  │
│ Creator          │───────────>│ :repo/git/refs/ │───────>│ dependabot/  │
│                  │            │ heads/:branch   │        │ ...          │
│ update_branch()  │            │                 │        │              │
│ - sha: def456    │            │ Body:           │        │ Updated ✅   │
│ - force: true    │            │ {               │        │ (force push) │
└──────────────────┘            │   sha: ...,     │        └──────────────┘
                                │   force: true   │
                                │ }               │
                                └─────────────────┘
```

## Summary: The Architectural Mismatch

```
                    Mirroring Model              vs          Dependabot Model
                    
┌────────────────────────────────┐        ┌────────────────────────────────┐
│  Assumptions:                  │        │  Assumptions:                  │
│  • Destination = Source        │        │  • Destination has extra refs  │
│  • No local changes            │        │  • PRs create branches         │
│  • Clean mirror                │        │  • Branches are temporary      │
│                                │        │                                │
│  Behavior:                     │        │  Behavior:                     │
│  • Delete extra branches       │        │  • Create branch when needed   │
│  • Keep only source branches   │        │  • Update branch for PR update │
│                                │        │  • Service deletes when closed │
└────────────────────────────────┘        └────────────────────────────────┘
                    ↓                                      ↓
              ┌─────────────────────────────────────────────────┐
              │         CONFLICT                                │
              │  Mirroring deletes what Dependabot creates      │
              └─────────────────────────────────────────────────┘
                                   ↓
              ┌─────────────────────────────────────────────────┐
              │         SOLUTION                                │
              │  • Branch protection prevents deletion          │
              │  • Modified mirroring skips Dependabot branches │
              └─────────────────────────────────────────────────┘
```
