# Updated PR Description for #14206

## Summary

I've prepared an updated PR description that properly addresses issue #14207. The updated description includes:

1. **"Fixes #14207"** reference at the top to link the PR to the issue
2. **Real-world impact section** showing the actual problem users experience
3. **Root cause explanation** to help reviewers understand the technical details
4. **All original technical details** about implementation and testing

## How to Apply

Since I don't have direct API access to update the PR, you'll need to manually update it:

1. Go to: https://github.com/dependabot/dependabot-core/pull/14206
2. Click "Edit" on the PR description
3. Replace the current description with the text below

---

## Updated PR Description

### What are you trying to accomplish?

Fixes #14207

The `ChangelogFinder` incorrectly identifies JSON files as changelogs when their names match changelog keywords. For example, `released-versions.json` triggers detection because it starts with "release" (in `CHANGELOG_NAMES`), causing raw JSON to appear in PR changelog sections.

**Real-world impact:** When Dependabot updates Gradle Wrapper and points to the `gradle/gradle` repository, it detects `released-versions.json` as a changelog, resulting in PRs displaying raw JSON like:

```
Changelog
<p><em>Sourced from <a href="https://github.com/gradle/gradle/blob/master/released-versions.json">gradle-wrapper's changelog</a>.</em></p>
<blockquote>
<p>{
&#34;latestReleaseSnapshot&#34;: {
&#34;version&#34;: &#34;9.4.0-20260215111606+0000&#34;,
...
```

This blocks PR #14132 where `gradle/gradle` contains `released-versions.json`.

### Anything you want to highlight for special attention from reviewers?

Added `.json` to file extension exclusions in `changelog_from_ref`, matching the existing `.sh` pattern:

```ruby
def changelog_from_ref(ref)
  files =
    dependency_file_list(ref)
    .select { |f| f.type == "file" }
    .reject { |f| f.name.end_with?(".sh") }
    .reject { |f| f.name.end_with?(".json") }  # Added
    .reject { |f| f.size > 1_000_000 }
    .reject { |f| f.size < 100 }

  select_best_changelog(files)
end
```

**Root cause:** The `CHANGELOG_NAMES` constant includes `release`, and the `select_best_changelog` method uses case-insensitive regex (`/\A#{name}/i`) to match files. Since `released-versions.json` starts with "release", it gets incorrectly selected as the changelog.

**Alternative considered:** Filtering by MIME type. Rejected as it requires fetching file content, adding latency and API calls.

### How will you know you've accomplished your goal?

- Test case added with fixture containing `released-versions.json`. Verifies nil return when only JSON files match changelog name patterns.
- All 54 existing tests in `changelog_finder_spec.rb` pass
- Rubocop and Sorbet type checking pass

### Checklist

- [x] I have run the complete test suite to ensure all tests and linters pass.
- [x] I have thoroughly tested my code changes to ensure they work as expected, including adding additional tests for new functionality.
- [x] I have written clear and descriptive commit messages.
- [x] I have provided a detailed description of the changes in the pull request, including the problem it addresses, how it fixes the problem, and any relevant details about the implementation.
- [x] I have ensured that the code is well-documented and easy to understand.

---

## Key Changes from Original Description

1. **Added "Fixes #14207"** - This creates an automatic link to the issue and will close it when the PR is merged
2. **Added "Real-world impact" section** - Shows the actual user-facing problem with an example of raw JSON appearing in PR bodies
3. **Added "Root cause" explanation** - Helps reviewers understand the technical reason for the bug
4. **Maintained all original content** - Testing details, implementation specifics, and checklist items remain unchanged

## Comparison to Issue #14207

The updated description directly addresses the issue by:
- Referencing the issue number (will auto-close on merge)
- Including the same example of raw JSON output shown in the issue
- Explaining the root cause as described in the issue
- Mentioning the Gradle Wrapper use case that triggered the discovery
- Referencing PR #14132 that is blocked by this bug

This makes it clear to reviewers why this fix is important and what real-world problem it solves.
