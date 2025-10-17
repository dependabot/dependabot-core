
@setup_workload begin
    @compile_workload begin
        # Test all function paths through run(input::String) exactly as dispatched
        # Each call exercises the JSON parsing, function routing, and result formatting

        # Get test file paths
        test_dir = joinpath(@__DIR__, "..", "test")
        test_project_path = joinpath(test_dir, "TestPackage.jl", "Project.toml")
        test_manifest_path = joinpath(test_dir, "TestPackage.jl", "Manifest.toml")

        # Helper function to run and check that result is not an error
        function run_check_result(input::String)
            result_json = run(input)
            result = JSON.parse(result_json)
            if haskey(result, "error")
                error_msg = result["error"]
                @warn "Precompile workload returned error for input: $(input)\n  Error: $(error_msg)"
            end
            return result_json
        end

        # Project/Manifest parsing functions
        run_check_result("""{"function": "parse_project", "args": {"project_path": "$test_project_path"}}""")
        run_check_result("""{"function": "parse_manifest", "args": {"manifest_path": "$test_manifest_path"}}""")

        # Update functions - TODO: make these real files
        run("""{"function": "update_manifest", "args": {"project_path": "/tmp/nonexistent", "updates": {"JSON": "0.21.4"}}}""")
        run("""{"function": "update_manifest", "args": {"project_path": "/tmp/nonexistent", "updates": {"JSON": "0.21.4"}}}""")

        # Version functions
        run_check_result("""{"function": "get_latest_version", "args": {"package_name": "JSON", "package_uuid": "682c06a0-de6a-54ab-a142-c8b1cf79cde6"}}""")
        run_check_result("""{"function": "fetch_package_versions", "args": {"package_name": "JSON", "package_uuid": "682c06a0-de6a-54ab-a142-c8b1cf79cde6"}}""")

        # Version constraint functions - use realistic constraints
        run_check_result("""{"function": "parse_julia_version_constraint", "args": {"constraint": "1.6"}}""")
        run_check_result("""{"function": "check_version_satisfies_constraint", "args": {"version": "1.6.0", "constraint": "1.6"}}""")
        run_check_result("""{"function": "expand_version_constraint", "args": {"constraint": "1.6"}}""")

        # Package metadata functions
        run_check_result("""{"function": "get_package_metadata", "args": {"package_name": "JSON", "package_uuid": "682c06a0-de6a-54ab-a142-c8b1cf79cde6"}}""")
        run_check_result("""{"function": "fetch_package_info", "args": {"package_name": "JSON", "package_uuid": "682c06a0-de6a-54ab-a142-c8b1cf79cde6"}}""")

        # Source URL functions
        run_check_result("""{"function": "find_package_source_url", "args": {"package_name": "JSON", "package_uuid": "682c06a0-de6a-54ab-a142-c8b1cf79cde6"}}""")
        run_check_result("""{"function": "extract_package_metadata_from_url", "args": {"package_name": "JSON", "source_url": "https://github.com/JuliaIO/JSON.jl"}}""")

        # Compatibility functions (use nonexistent paths to avoid actual updates)
        run("""{"function": "check_update_compatibility", "args": {"project_path": "/tmp/nonexistent", "package_name": "JSON", "target_version": "0.21.4"}}""")
        run("""{"function": "resolve_dependencies_with_constraints", "args": {"project_path": "/tmp/nonexistent", "target_updates": {"JSON": "0.21.4"}}}""")

        # Test unknown function path - exercises error handling (expected to return error)
        run("""{"function": "unknown_function", "args": {}}""")

        # Test JSON parsing error path (expected to return error)
        run("""invalid json""")

        # Test missing function field (expected to return error)
        run("""{"args": {"package_name": "JSON"}}""")

        # Test missing args field (expected to return error)
        run("""{"function": "get_latest_version"}""")
    end
end
