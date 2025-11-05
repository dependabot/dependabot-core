# Python Version Selection Investigation - Summary

## Issue Investigated
**Report**: Dependabot ignores `requires-python` in pyproject.toml and uses Python 3.13/3.14 instead of minimum version (e.g., 3.9)

## Investigation Outcome
✅ **The reported bug does NOT exist in the current dependabot-core codebase.**

## Testing Conducted

### 1. Manual Testing
Verified with live code execution in Docker container:
- `requires-python = ">= 3.9, <3.13"` → Correctly selects **Python 3.9.24** ✅
- No requires-python → Correctly defaults to **Python 3.14.0** ✅
- Poetry `python = "^3.10"` → Correctly selects **Python 3.10.19** ✅

### 2. Unit Tests Added
- **python_requirement_parser_spec.rb**: Tests for pyproject.toml parsing
- **language_version_manager_spec.rb**: Tests for version selection logic

### 3. Regression Testing
All existing tests pass with no regressions:
- ✅ 95 file_parser tests
- ✅ 52 requirement tests  
- ✅ 7 language tests
- ✅ 9 python_requirement_parser tests

## Root Cause Analysis

The code correctly implements lowest-compatible-version selection:

```ruby
# python/lib/dependabot/python/language_version_manager.rb:105
version = Language::PRE_INSTALLED_PYTHON_VERSIONS.find { |v| requirement.satisfied_by?(v) }
```

Since `PRE_INSTALLED_PYTHON_VERSIONS` is sorted ascending, `.find` returns the **first** (lowest) matching version.

## Why Users Might Experience Issues

The paradox: User reports `.python-version` file "fixes" the issue, but `.python-version` has **lower priority** than `pyproject.toml`. This suggests:

1. **Issue Already Fixed**: Problem existed in older version, now fixed in main
2. **dependabot-api Layer**: File fetching or config issues outside dependabot-core
3. **Parsing Failures**: Malformed pyproject.toml fails silently  
4. **File Not Fetched**: Some scenarios don't fetch pyproject.toml

## Recommendations

### For Users Experiencing Issues
1. Verify pyproject.toml has valid TOML syntax
2. Ensure `requires-python` is under `[project]` section (PEP 621 format)
3. Check logs to confirm pyproject.toml is being read
4. Use `.python-version` as temporary workaround
5. Report specific repository exhibiting issue

### For Maintainers
1. Add logging when pyproject.toml parsing fails
2. Add warning when defaulting to latest Python version
3. Document Python version selection behavior
4. Consider explicit `python-version` in dependabot.yml (requires API changes)

## Files Modified

1. **python/spec/dependabot/python/file_parser/python_requirement_parser_spec.rb**
   - Added tests for PEP 621 requires-python parsing
   - Added tests for Poetry python dependency
   - Added test for missing Python version

2. **python/spec/dependabot/python/language_version_manager_spec.rb** (NEW)
   - Comprehensive tests for version selection
   - Tests for range constraints, exact versions, defaults
   - Tests for both PEP 621 and Poetry formats

## Conclusion

**No code changes to dependabot-core are required.** The current implementation:
- ✅ Correctly selects lowest compatible Python version
- ✅ Properly parses pyproject.toml requirements
- ✅ Has comprehensive test coverage
- ✅ Follows expected priority order

If users continue experiencing issues, investigation should focus on:
- dependabot-api (file fetching layer)
- Specific repository configurations
- Production deployment vs local testing differences
