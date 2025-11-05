# Investigation: Python Version Selection Issue

## Issue Summary
User reports that Dependabot ignores `requires-python` in `pyproject.toml` and uses Python 3.13/3.14 instead of the minimum specified version (e.g., 3.9).

## Investigation Results

### Current Behavior (Verified in dependabot-core)

The code in `python/lib/dependabot/python/language_version_manager.rb` **correctly** selects the lowest compatible Python version:

1. **Test Case 1**: `requires-python = ">= 3.9, <3.13"`
   - ✅ Selects Python 3.9.24 (lowest compatible)

2. **Test Case 2**: No `requires-python` specified
   - ✅ Selects Python 3.14.0 (latest/default)

3. **Test Case 3**: Poetry format `python = "^3.10"`
   - ✅ Selects Python 3.10.19 (lowest compatible)

### Code Logic

File: `python/lib/dependabot/python/language_version_manager.rb`

```ruby
# Line 105: Find first (lowest) matching version
version = Language::PRE_INSTALLED_PYTHON_VERSIONS.find { |v| requirement.satisfied_by?(v) }
```

Since `PRE_INSTALLED_PYTHON_VERSIONS` is sorted in ascending order (from `language.rb` line 30), `.find` returns the **lowest** matching version.

### Priority Order of Version Sources

From `python/lib/dependabot/python/file_parser/python_requirement_parser.rb` lines 27-36:

1. Pipfile (`python_version` or `python_full_version`)
2. **pyproject.toml** (`[project] requires-python` or `[tool.poetry.dependencies] python`)
3. pip-compile header
4. `.python-version` file
5. `runtime.txt`
6. `setup.py` (`python_requires`)

### Paradox in User Report

The user states that adding `.python-version` **fixes** the issue. However:
- `.python-version` has **lower priority** than `pyproject.toml`
- If `pyproject.toml` was being read correctly, `.python-version` would be ignored
- This suggests `pyproject.toml` might not be fetched/parsed in their scenario

## Possible Causes

### 1. Issue Already Fixed
The issue may have been fixed in a recent commit. The current codebase works correctly.

### 2. Issue in dependabot-api (Not in dependabot-core)
The problem might be in how dependabot-api:
- Fetches dependency files
- Passes configuration to dependabot-core
- Handles pyproject.toml files

### 3. File Fetching Issue
In certain repository configurations, `pyproject.toml` might not be fetched or passed to the FileParser.

### 4. Parsing Error
A malformed `pyproject.toml` might cause silent parsing failure, falling back to default (latest) Python version.

## Recommendations

### For Users (Immediate)
1. **Workaround**: Add `.python-version` file with desired version
2. **Verify**: Check that `pyproject.toml` has correct TOML syntax
3. **Check**: Ensure `requires-python` is under `[project]` section (PEP 621 format)

### For Developers (Short Term)
1. **Add Error Logging**: Log when `pyproject.toml` parsing fails
2. **Add Warning**: Warn when falling back to default Python version
3. **Improve Documentation**: Document Python version selection behavior

### For Developers (Long Term - Feature Request)
Add explicit `python-version` configuration to `dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "weekly"
    python-version: "3.9"  # Explicit version control
```

**Note**: This requires changes in both dependabot-api and the configuration schema, which are outside the scope of dependabot-core.

## Tests Added

Added comprehensive tests in `python/spec/dependabot/python/file_parser/python_requirement_parser_spec.rb`:
- Test for PEP 621 `requires-python` field
- Test for Poetry `python` dependency
- Test for projects without Python version specified

All tests pass, confirming current behavior is correct.

## Conclusion

**The reported issue does NOT exist in the current dependabot-core codebase.** 

The issue is likely:
1. Already fixed in main branch
2. In dependabot-api (not dependabot-core)
3. Related to specific repository configurations not covered by current tests

Further investigation would require:
- Access to dependabot-api repository
- Specific example repository exhibiting the issue
- Production logs showing incorrect Python version selection
