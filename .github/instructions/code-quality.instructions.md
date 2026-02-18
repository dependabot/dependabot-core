---
applyTo: "**/*.rb"
---

# Code Quality Guidelines

## Pre-Commit Checklist

**Do NOT commit or push changes until ALL of the following pass inside a Docker container:**

1. `rubocop` — Passes with no offenses (use `rubocop -A` to auto-fix)
2. `bundle exec srb tc` — Sorbet type checking passes (for production code)
3. `rspec spec/path/to/relevant_spec.rb` — Tests covering your changes pass

Run these via `bin/test`:

- `bin/test {ecosystem} rubocop`
- `bin/test {ecosystem} spec/path/to/spec.rb`

For Sorbet, run from the repo root inside the container:

- `bin/docker-dev-shell {ecosystem}` then `cd /home/dependabot && bundle exec srb tc`

When delegating work to sub-agents, each agent must validate its own changes before committing.

## RuboCop Best Practices

Avoid adding RuboCop exceptions unless absolutely necessary. Resolve offenses using proper coding practices:

- **Method extraction** — Break large methods into smaller, focused methods
- **Class extraction** — Split large classes into single-responsibility classes
- **Reduce complexity** — Simplify conditional logic and nested structures
- **Improve naming** — Use clear, descriptive variable and method names
- **Refactor long parameter lists** — Use parameter objects or configuration classes
- **Extract constants** — Move magic numbers and strings to named constants

If a RuboCop exception is truly unavoidable, provide clear justification in a comment explaining why the rule cannot be followed and what alternatives were considered.

## Sorbet Type Checking

- All new files must use `# typed: strict` at minimum
- Existing files below `strict`: upgrade to `strict` when making changes
- Add explicit type signatures for method parameters and return values
- Always validate with `bundle exec srb tc`

### Autocorrect Usage

Use `bundle exec srb tc -a` **cautiously** — it often creates incorrect fixes for complex cases.

Autocorrect is acceptable for simple cases:

- Missing `override.` annotations
- `T.let` declarations for instance variables
- Constant type annotations

Always manually resolve complex type mismatches, method signature issues, and structural problems. Review any autocorrected changes carefully.

## Code Comments

Prioritize self-documenting code over comments. Prefer extracting well-named methods over adding explanatory comments.

### DO Comment

- **Business logic context** — Explain *why* something is done when not obvious
- **Complex algorithms** — Document the approach or concepts
- **Workarounds** — Explain why a non-obvious solution was necessary
- **External constraints** — API limitations, ecosystem-specific behaviors
- **TODOs** — With issue references when possible

### DON'T Comment

- **Implementation decisions** — Don't explain what was *not* implemented
- **Obvious code** — Don't restate what the code clearly does
- **Apologies or justifications** — Suggests code quality issues
- **Outdated information** — Remove comments that no longer apply
- **Version history** — Use git history instead

### Example

```ruby
# Good: Explains WHY
# Retry up to 3 times due to GitHub API rate limiting
retry_count = 3

# Bad: Explains WHAT (obvious from code)
# Set retry count to 3
retry_count = 3

# Good: Documents external constraint
# GitHub API requires User-Agent header or returns 403
headers["User-Agent"] = "Dependabot/1.0"
```
