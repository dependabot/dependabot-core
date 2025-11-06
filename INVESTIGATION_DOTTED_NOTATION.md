# Investigation: Dynamic Field Parsing in pyproject.toml

## Issue Report
User reported that pyproject.toml files using dotted notation for `tool.setuptools.dynamic.version` fail with "/pyproject.toml not parseable" error.

### Reported Non-Working Example
```toml
[tool.setuptools]
dynamic.version = {attr = "test.__init__.__version__"}

[project]
name = "test"
dynamic = ["version"]
```

### Reported Working Example  
```toml
[tool.setuptools.dynamic]
version = {attr = "test.__init__.__version__"}

[project]
name = "test"
dynamic = ["version"]
```

## Investigation Results

### 1. Dotted Notation Support
**Result: WORKS CORRECTLY**

Both TOML parsers used by Dependabot correctly handle dotted notation:
- TomlRB (Ruby): Parses `dynamic.version` as nested structure
- tomli (Python): Parses `dynamic.version` as nested structure

Testing confirmed:
```ruby
# Tested with both parsers - both succeed
[tool.setuptools]
dynamic.version = {attr = "test.__init__.__version__"}
```

### 2. Edge Case: Table Redefinition
**Result: CORRECTLY REJECTED PER TOML SPEC**

The ONLY scenario that fails is when TOML table redefinition occurs:

```toml
# This FAILS (correctly per TOML spec)
[tool.setuptools.dynamic]
dependencies = {file = ["requirements.txt"]}

[tool.setuptools]
dynamic.version = {attr = "..."}  # ERROR: redefines 'dynamic' table
```

Both parsers correctly raise errors:
- TomlRB: `ValueOverwriteError - Key "dynamic" is defined more than once`
- tomli: `TOMLDecodeError - Cannot redefine namespace`

### 3. Full Integration Testing
**Result: ALL TESTS PASS**

Tested the complete flow:
1. File Fetcher + TOML parsing ✓
2. Pyproject Files Parser ✓
3. Full File Parser ✓
4. With dependencies ✓
5. Without dependencies ✓
6. With __init__.py file ✓

ALL scenarios work correctly with dotted notation.

## Conclusions

### No Bug Found
The reported issue cannot be reproduced. The minimal example provided by the user works correctly in current Dependabot code.

### Possible Explanations
1. **Issue Already Fixed**: Bug may have been fixed in a previous update
2. **Missing Context**: User's actual pyproject.toml may have additional content causing issues
3. **TOML Spec Violation**: User's file may violate TOML spec (table redefinition)
4. **Misunderstanding**: User may have confused error messages or contexts

### Valid TOML Patterns

✅ **Dotted notation only:**
```toml
[tool.setuptools]
dynamic.version = {attr = "..."}
```

✅ **Section notation only:**
```toml
[tool.setuptools.dynamic]
version = {attr = "..."}
```

✅ **Mixed - dotted first:**
```toml
[tool.setuptools]
dynamic.version = {attr = "..."}

[tool.setuptools.dynamic]
dependencies = {file = ["..."]}
```

❌ **Mixed - section first (INVALID PER TOML SPEC):**
```toml
[tool.setuptools.dynamic]
dependencies = {file = ["..."]}

[tool.setuptools]
dynamic.version = {attr = "..."}  # Redefines 'dynamic'
```

## Recommendations

### For This Issue
1. Request complete pyproject.toml from user
2. Verify Dependabot version user is running
3. Check if issue still reproduces with latest version
4. If not reproducible, close as "Cannot Reproduce"

### For Users
If encountering TOML parsing errors:
1. Validate TOML syntax at https://www.toml-lint.com/
2. Ensure tables are not redefined
3. Use consistent notation (all dotted OR all section headers)
4. If mixing notations, put dotted keys before section headers

## Test Coverage Added
- Fixture: `dynamic_nested_dotted.toml` - Minimal dotted notation example
- Fixture: `dynamic_nested_dotted_with_deps.toml` - With dependencies
- Test case: Added to `pyproject_files_parser_spec.rb` to verify dotted notation parsing

## Files Modified
- `python/spec/fixtures/pyproject_files/dynamic_nested_dotted.toml` (new)
- `python/spec/fixtures/pyproject_files/dynamic_nested_dotted_with_deps.toml` (new)
- `python/spec/dependabot/python/file_parser/pyproject_files_parser_spec.rb` (updated)
