# Support Response Template - Dependabot Branch Mirroring Issue

## For Support Team Use

This template can be used to respond to the WordPress customer regarding their Dependabot branch deletion issue.

---

## Response to Customer

### Subject: Analysis of Dependabot Branch Deletion During Repository Mirroring

Hi [Customer Name],

Thank you for reporting this issue and for your patience while we investigated. We've completed a comprehensive analysis of how Dependabot creates and manages branches, and how this interacts with repository mirroring.

### TL;DR - Root Cause Identified

**The issue is an architectural incompatibility between repository mirroring and Dependabot:**

Your repository mirrors from an external SVN repository to GitHub. When mirroring runs, it synchronizes branches from the source (SVN) to the destination (GitHub). Since Dependabot branches exist only in GitHub (not in the SVN source), the mirroring operation deletes them as "extra" branches that don't exist in the source.

This is expected behavior for repository mirroring - it's designed to make the destination an exact copy of the source.

### Investigation Results

We analyzed the Dependabot Core codebase and found:

1. **Dependabot branches are regular Git branches** - They're stored as standard `refs/heads/dependabot/*` references with no special protection mechanism
2. **No special marking** - Git tools can't distinguish Dependabot branches from user-created branches
3. **No code changes around February 2024** in the Dependabot Core repository that would explain the behavior change you observed

**Important:** The change you noticed likely occurred in GitHub's Dependabot service or repository mirroring service (not in the open-source Dependabot Core). We're investigating this separately with the platform team.

### Immediate Solution (Recommended)

**Option 1: Branch Protection Rule**

This is the most effective solution and requires minimal ongoing maintenance:

1. Go to your repository: **Settings → Branches → Branch protection rules**
2. Click **Add rule**
3. Configure:
   - **Branch name pattern:** `dependabot/**`
   - **☑ Allow force pushes** (required for Dependabot to update branches)
   - **☑ Restrict deletions** (prevents mirroring from deleting branches)
4. Save changes

**Result:** The mirroring script will be unable to delete Dependabot branches, but Dependabot can still update them.

### Alternative Solutions

**Option 2: Modify Your Mirroring Script**

Update your custom mirroring script to skip Dependabot branches:

```bash
# Example modification
for branch in $branches_to_delete; do
  # Skip Dependabot branches
  if [[ $branch =~ ^dependabot/ ]]; then
    continue
  fi
  
  # Delete other non-source branches
  git push origin --delete "$branch"
done
```

**Option 3: Selective Push Instead of Mirror Sync**

Change from a full mirror sync to selective push:

```bash
# Only push branches that exist in source
for branch in $(svn list branches); do
  git push origin "svn/$branch:$branch" --force
done

# Don't delete any branches - let GitHub manage Dependabot branches
```

### Why This Happened

Your observation about February 2024 is valuable. While we didn't find changes in the open-source code, the behavior change you noticed could be due to:

1. **GitHub's Dependabot service** changing how/when it creates or deletes PR branches
2. **GitHub's mirroring service** changing how it handles branch synchronization
3. **Branch cleanup policies** being updated to be more aggressive
4. **Your mirroring frequency** changing (you mentioned it used to run every 15 minutes, now runs on-commit)

We're investigating this timeline separately, but the branch protection solution will work regardless of what changed.

### Technical Details

For your engineering team, we've created comprehensive documentation:

- **[Complete Analysis](./branch-lifecycle-analysis.md)** - Deep technical dive into Dependabot's branch logic
- **[Quick Reference](./branch-mirroring-conflict-summary.md)** - Summary of findings and solutions
- **[Visual Diagrams](./branch-mirroring-diagrams.md)** - Flow diagrams explaining the conflict
- **[Documentation Index](./README.md)** - Overview of all resources

### Next Steps

1. **Immediate action:** Implement branch protection rule for `dependabot/**` (Option 1 above)
2. **Verify:** Wait for next Dependabot run and confirm branches are preserved
3. **Monitor:** Check that mirroring continues to work for your SVN branches
4. **Adjust if needed:** If Option 1 doesn't work for your setup, try Option 2 or 3

### Additional Notes

- **Branch protection is safe:** It only prevents deletion, not updates
- **Dependabot will still work:** Force push is enabled, so PR updates work normally
- **Your workflow is preserved:** SVN branches continue to sync normally
- **No code changes needed:** This is a configuration change only

### Questions?

If you have any questions or if the branch protection solution doesn't resolve the issue, please let us know. We're here to help!

Best regards,
[Your Name]
GitHub Support

---

## Internal Notes for Support Team

### Key Points to Remember

1. **This is not a bug** - It's expected behavior for repository mirroring
2. **The customer's timeline observation is valid** - Something changed around Feb 2024, but not in the open-source codebase
3. **Branch protection is the best solution** - It's maintained by GitHub and requires no script changes
4. **The change is likely in GitHub's services** - Not in the open-source Dependabot Core

### If Customer Pushes Back

**"But it worked before February 2024"**
- Acknowledge that something changed
- Explain that the change was likely in GitHub's services, not the open-source code
- Branch protection solution works regardless of what changed
- We're investigating the platform change separately

**"Can't you just make Dependabot branches special?"**
- Technically possible but would be a significant platform change
- Branch protection achieves the same goal more simply
- Would affect all repositories, not just theirs
- Branch protection is the recommended approach

**"Will this affect our SVN mirroring?"**
- No, branch protection only affects deletion of `dependabot/**` branches
- SVN branches sync normally
- Mirroring can still create, update, and delete SVN-sourced branches

### Escalation Path

If branch protection doesn't resolve the issue:
1. Verify they've configured the rule correctly (pattern must be `dependabot/**`)
2. Check if they have GitHub Enterprise with different branch protection behavior
3. Escalate to platform team to investigate the February 2024 change
4. Consider temporary workaround with modified mirroring script (Option 2)

### Success Metrics

✅ Branch protection rule implemented
✅ Dependabot branches preserved during mirroring
✅ Dependabot PRs continue to work
✅ SVN mirroring continues to work
✅ Customer satisfied with solution

---

## References

- [Complete Technical Analysis](./branch-lifecycle-analysis.md)
- [Code Locations](./README.md#code-locations-analyzed)
- [Visual Diagrams](./branch-mirroring-diagrams.md)
- GitHub Docs: [Branch Protection Rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches)

## Issue Tracking

- **Zendesk Ticket:** 3495916
- **Repository:** wordpress/wordpress-develop
- **Issue Type:** Support Escalation (Sev2)
- **Date Analyzed:** 2025-10-28
