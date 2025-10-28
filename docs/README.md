# Dependabot Branch Mirroring Issue - Documentation

This directory contains analysis and documentation for the Dependabot branch mirroring conflict issue reported by WordPress.

## Issue Summary

WordPress's `wordpress-develop` repository uses repository mirroring from an external SVN repository to GitHub. They observed that Dependabot branches were being deleted during mirroring operations, reportedly starting around February 2024.

## Documentation Files

### 1. [branch-lifecycle-analysis.md](./branch-lifecycle-analysis.md)
**Comprehensive Technical Analysis** (17KB, ~485 lines)

Complete deep-dive into Dependabot's branch creation and deletion logic, including:
- How Dependabot creates branches
- How Dependabot deletes/closes branches
- Key characteristics of Dependabot branches
- Interaction with repository mirroring
- Timeline analysis (February 2024)
- Technical details of branch lifecycle
- Analysis of mirroring conflict
- Detailed recommendations
- Code references and locations

**Best for:** Engineering teams needing complete technical understanding

### 2. [branch-mirroring-conflict-summary.md](./branch-mirroring-conflict-summary.md)
**Quick Reference Guide** (6KB, ~190 lines)

Condensed version highlighting the most important information:
- Problem statement
- Root cause
- Key findings from code analysis
- Immediate solutions (3 options)
- Code flow summary
- Investigation notes

**Best for:** Support teams and quick troubleshooting

### 3. [branch-mirroring-diagrams.md](./branch-mirroring-diagrams.md)
**Visual Flow Diagrams** (15KB, ~309 lines)

ASCII art diagrams illustrating:
- Problem overview
- Normal Dependabot workflow
- Mirroring conflict scenario
- Solution implementations
- Branch reference structure
- Branch naming patterns
- Technical flow diagrams
- Architectural mismatch explanation

**Best for:** Visual learners and stakeholder presentations

## Quick Reference

### Root Cause
**Architectural mismatch:**
- Repository mirroring expects destination to be exact copy of source
- Dependabot creates branches directly in destination (GitHub)
- Dependabot branches don't exist in source (SVN)
- Mirroring deletes branches that aren't in source

### Key Finding
**No changes in dependabot-core around February 2024** that would explain the behavior change. The change likely occurred in:
- GitHub's Dependabot service (not in this repository)
- GitHub's repository mirroring service
- Branch cleanup policies

### Immediate Solutions

#### Option 1: Branch Protection (Recommended)
```
Settings → Branches → Add rule
Pattern: dependabot/**
☑ Allow force pushes
☑ Restrict deletions
```

#### Option 2: Modify Mirroring Script
```bash
# Skip Dependabot branches during deletion
if [[ ! $branch =~ ^dependabot/ ]]; then
  git push origin --delete "$branch"
fi
```

#### Option 3: Selective Push
```bash
# Only push source branches, don't delete others
for branch in $(svn list branches); do
  git push origin "svn/$branch:$branch" --force
done
```

## Code Locations Analyzed

Key files examined in this analysis:

```
common/lib/dependabot/
├── pull_request_creator.rb          # Main PR creation orchestration
├── pull_request_creator/
│   ├── github.rb                    # GitHub branch/PR logic (lines 363-394)
│   ├── branch_namer.rb              # Branch naming strategies
│   └── branch_namer/
│       └── solo_strategy.rb         # Branch naming implementation

updater/lib/dependabot/
├── api_client.rb                    # API client (lines 91-109)
└── updater/
    └── operations/                  # Update operations
        ├── refresh_version_update_pull_request.rb
        ├── refresh_group_update_pull_request.rb
        └── refresh_security_update_pull_request.rb
```

## Investigation Methodology

1. ✅ Examined all branch creation code
2. ✅ Reviewed branch naming strategies
3. ✅ Analyzed PR closing and deletion logic
4. ✅ Searched git history for February 2024 changes
5. ✅ Reviewed branch protection mechanisms
6. ✅ Documented branch lifecycle
7. ❌ No relevant changes found in dependabot-core

## Conclusion

The issue is a **fundamental architectural incompatibility** between repository mirroring and Dependabot's workflow. Dependabot branches are regular Git branches with no special protection against deletion by external tools.

**Solution:** Implement branch protection rules or modify mirroring script to exclude Dependabot branches.

**February 2024 Timeline:** No changes found in dependabot-core codebase. Any behavioral change occurred in GitHub's services (Dependabot service or mirroring service), not in this repository.

## Related GitHub Issues

- Original Issue: Repository Mirroring and Dependabot branches
- Customer: wordpress/wordpress-develop
- Zendesk Ticket: 3495916

## Contact

For questions about this analysis, please refer to the original issue or contact the @github/repos team.

---

**Last Updated:** 2025-10-28  
**Analysis By:** GitHub Copilot (via copilot-workspace agent)  
**Issue Type:** Support Escalation (Sev2)
