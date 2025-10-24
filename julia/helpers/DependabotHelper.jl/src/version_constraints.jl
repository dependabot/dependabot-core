# Version constraint parsing and validation functions for DependabotHelper.jl
#
# These functions implement the official Julia Pkg.jl version constraint
# specification as documented at:
# https://pkgdocs.julialang.org/v1/compatibility/#Version-specifier-format
#
# Supported constraint formats:
# - Caret specifiers: ^1.2.3 (allows [1.2.3, 2.0.0))
# - Tilde specifiers: ~1.2.3 (allows [1.2.3, 1.3.0))
# - Inequality specifiers: >=1.2.3, <2.0.0
# - Hyphen specifiers: 1.2.3 - 4.5.6
# - Comma-separated: 1.2, 2
# - Exact versions: 1.2.3
# - Wildcard: * (matches any version)
#
# Special handling for 0.x versions follows semver rules:
# - ^0.2.3 means [0.2.3, 0.3.0)
# - ^0.0.3 means [0.0.3, 0.0.4)

"""
    convert_to_julia_constraint(constraint::String)

Convert various constraint formats to Julia-compatible version constraints using semver_spec.

This function handles preprocessing for edge cases that semver_spec doesn't support directly,
such as wildcard (*) constraints and double equals (==) operators.

For standard constraint formats (^, ~, >=, <, hyphen ranges, comma-separated),
the original constraint is returned as-is since semver_spec handles them correctly.
"""
function convert_to_julia_constraint(constraint::String)
    constraint = strip(constraint)

    # Handle empty or wildcard constraints (semver_spec doesn't support these)
    if isempty(constraint) || constraint == "*"
        return "*"
    end

    # Handle double equals (convert to single equals for exact match)
    if startswith(constraint, "==")
        constraint = "=" * constraint[3:end]
    end

    # Try to use Julia's semver_spec which handles:
    # - Caret constraints: ^1.2.3
    # - Tilde constraints: ~1.2.3
    # - Inequality operators: >=1.2.3, <1.2.3
    # - Hyphen ranges: 1.2.3 - 4.5.6
    # - Comma-separated: 1.2, 2
    # - Exact versions: 1.2.3
    try
        version_spec = Pkg.Types.semver_spec(constraint)
        return constraint  # Return original constraint if semver_spec can parse it
    catch ex
        @error "convert_to_julia_constraint: Failed to convert constraint" constraint=constraint exception=(ex, catch_backtrace())
        # If semver_spec fails, try some fallback handling

        # Handle exact match with equals
        if startswith(constraint, "=")
            version_part = constraint[2:end]
            try
                Pkg.Types.VersionNumber(version_part)  # Validate it's a valid version
                return version_part  # Return just the version part
            catch
                return constraint
            end
        end

        # For any other invalid format, return as-is and let caller handle the error
        return constraint
    end
end

"""
    parse_julia_version_constraint(constraint::String)

Parse a Julia version constraint string into a structured format using the official
Pkg.jl semver_spec function.

Supports all official Julia version constraint formats:
- Caret constraints: ^1.2.3 (compatible upgrades, follows semver)
- Tilde constraints: ~1.2.3 (patch-level changes only)
- Inequality constraints: >=1.2.3, <2.0.0
- Hyphen ranges: 1.2.3 - 4.5.6
- Comma-separated: 1.2, 2
- Exact versions: 1.2.3
- Wildcard: * (any version)

Returns a Dict with keys:
- "type": "parsed", "wildcard", or "error"
- "constraint": original constraint string (for parsed)
- "version_spec": "*" (for wildcard)
- "error": error message (for error)
"""
function parse_julia_version_constraint(constraint::String)
    try
        # Handle wildcard constraints (semver_spec doesn't support these)
        if isempty(constraint) || constraint == "*"
            return Dict(
                "type" => "wildcard",
                "version_spec" => "*"
            )
        end

        # Use Julia's semver_spec to parse the constraint
        # This handles ^, ~, >=, <, hyphen ranges, comma-separated, etc.
        version_spec = Pkg.Types.semver_spec(constraint)

        return Dict(
            "type" => "parsed",
            "constraint" => constraint
        )
    catch ex
        @error "parse_julia_version_constraint: Failed to parse constraint" constraint=constraint exception=(ex, catch_backtrace())
        return Dict(
            "type" => "error",
            "error" => sprint(showerror, ex)
        )
    end
end

"""
    check_version_satisfies_constraint(version::String, constraint::String)

Check if a version satisfies a given constraint using Julia's official semver_spec.

Uses the same constraint parsing logic as Julia's Pkg manager, ensuring compatibility
with all standard version constraint formats used in Project.toml [compat] sections.

Args:
- version: Version string to test (e.g., "1.2.3")
- constraint: Constraint string (e.g., "^1.0", "~1.2.3", ">=1.0", etc.)

Returns:
- Boolean: true if version satisfies constraint, false otherwise

Special handling:
- "*" constraint always returns true
- Invalid versions or constraints return false
"""
function check_version_satisfies_constraint(version::String, constraint::String)
    try
        # Parse the version
        parsed_version = Pkg.Types.VersionNumber(version)

        # Handle wildcard constraint
        if constraint == "*"
            return true
        end

        # Use Julia's semver_spec to parse the constraint
        version_spec = Pkg.Types.semver_spec(constraint)

        # Check if version satisfies constraint
        satisfies = parsed_version in version_spec

        return satisfies
    catch ex
        @error "check_version_satisfies_constraint: Failed to check version constraint" version=version constraint=constraint exception=(ex, catch_backtrace())
        return false
    end
end

"""
    expand_version_constraint(constraint::String)

Expand a version constraint to show example versions that would match.

Uses Julia's official semver_spec to parse the constraint, then generates
example version numbers that satisfy the constraint. This helps understand
what versions would be considered compatible.

Returns a Dict with keys:
- "type": "constraint", "wildcard", or "error"
- "original": original constraint string
- "ranges": array of example version strings that match
- "description": human-readable description (for wildcard)
- "error": error message (for error)

Note: This generates example versions for demonstration purposes.
In practice, you would query actual available package versions.
"""
function expand_version_constraint(constraint::String)
    try
        # Handle wildcard constraints
        if isempty(constraint) || constraint == "*"
            return Dict(
                "type" => "wildcard",
                "description" => "Matches any version"
            )
        end

        # Use Julia's semver_spec to parse the constraint
        version_spec = Pkg.Types.semver_spec(constraint)

        # Generate some example versions that would match
        examples = []

        # This is a simplified expansion - in practice, you'd query available versions
        for major in 0:5
            for minor in 0:9
                for patch in 0:9
                    test_version = Pkg.Types.VersionNumber("$major.$minor.$patch")
                    if test_version in version_spec && length(examples) < 10
                        push!(examples, string(test_version))
                    end
                end
            end
        end

        return Dict(
            "type" => "constraint",
            "original" => constraint,
            "ranges" => examples
        )
    catch ex
        @error "expand_version_constraint: Failed to expand constraint" constraint=constraint exception=(ex, catch_backtrace())
        return Dict(
            "type" => "error",
            "error" => sprint(showerror, ex)
        )
    end
end
