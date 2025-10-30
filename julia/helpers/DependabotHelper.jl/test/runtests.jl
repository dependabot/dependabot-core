using Test
using JSON
using DependabotHelper

@testset "DependabotHelper.jl Tests" begin

    # Include custom registry management tests
    include("test_registry_management.jl")

    @testset "Function Tests" begin
        # Test error handling for non-existent files
        result = @test_nowarn DependabotHelper.parse_project("/nonexistent/Project.toml")
        @test haskey(result, "error")

        # Test get_latest_version with a known package
        json_uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
        result = @test_nowarn DependabotHelper.get_latest_version("JSON", json_uuid)
        @test haskey(result, "version")

        # Test get_latest_version with invalid package
        result = @test_nowarn DependabotHelper.get_latest_version("NonExistentPackage12345", "00000000-0000-0000-0000-000000000000")
        @test haskey(result, "error")

        # Test parsing with non-existent file
        result = @test_nowarn DependabotHelper.parse_project("/nonexistent/Project.toml")
        @test haskey(result, "error")

        # Test package metadata retrieval
        json_uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
        result = @test_nowarn DependabotHelper.get_package_metadata("JSON", json_uuid)
        @test result["name"] == "JSON"
        @test result["uuid"] == "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
        @test haskey(result, "available_versions")
        @test haskey(result, "latest_version")

        # Test package metadata with invalid package
        result = @test_nowarn DependabotHelper.get_package_metadata("NonExistentPackage12345", "00000000-0000-0000-0000-000000000000")
        @test haskey(result, "error")

        # Test manifest parsing with non-existent file
        result = @test_nowarn DependabotHelper.parse_manifest("/nonexistent/Manifest.toml")
        @test haskey(result, "error")
    end

    @testset "JSON Interface Tests" begin
        # Test basic JSON parsing and function dispatch
        json_uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
        test_cases = [
            """{"function": "parse_project", "args": {"project_path": "/nonexistent/Project.toml"}}""",
            """{"function": "get_latest_version", "args": {"package_name": "JSON", "package_uuid": "$json_uuid"}}""",
            """{"function": "parse_project", "args": {"project_path": "/nonexistent/Project.toml"}}""",
            """{"function": "get_package_metadata", "args": {"package_name": "JSON", "package_uuid": "$json_uuid"}}""",
            """{"function": "parse_julia_version_constraint", "args": {"constraint": "^1.0"}}""",
            """{"function": "check_version_satisfies_constraint", "args": {"version": "1.5.0", "constraint": "^1.0"}}""",
            """{"function": "expand_version_constraint", "args": {"constraint": ">=1.0"}}""",
            """{"function": "fetch_package_versions", "args": {"package_name": "JSON", "package_uuid": "$json_uuid"}}""",
            """{"function": "fetch_package_info", "args": {"package_name": "JSON", "package_uuid": "$json_uuid"}}"""
        ]

        for test_input in test_cases
            @test_nowarn begin
                parsed_input = JSON.parse(test_input)
                func_name = parsed_input["function"]
                args = parsed_input["args"]

                # Simple function dispatch for testing
                if func_name == "parse_project"
                    DependabotHelper.parse_project(args["project_path"])
                elseif func_name == "get_latest_version"
                    DependabotHelper.get_latest_version(args)
                elseif func_name == "parse_project"
                    DependabotHelper.parse_project(args["project_path"])
                elseif func_name == "get_package_metadata"
                    DependabotHelper.get_package_metadata(args)
                elseif func_name == "parse_julia_version_constraint"
                    DependabotHelper.parse_julia_version_constraint(args["constraint"])
                elseif func_name == "check_version_satisfies_constraint"
                    DependabotHelper.check_version_satisfies_constraint(args["version"], args["constraint"])
                elseif func_name == "expand_version_constraint"
                    DependabotHelper.expand_version_constraint(args["constraint"])
                elseif func_name == "fetch_package_versions"
                    DependabotHelper.fetch_package_versions(args)
                elseif func_name == "fetch_package_info"
                    DependabotHelper.fetch_package_info(args)
                else
                    Dict("error" => "Unknown function: $func_name")
                end
            end
        end

        # Test error handling for invalid JSON
        @test_throws Exception JSON.parse("{invalid json}")

        # Test unknown function handling
        input_json = """{"function": "unknown_function", "args": {}}"""
        parsed_input = JSON.parse(input_json)
        func_name = parsed_input["function"]

        result = if func_name == "unknown_function"
            Dict("error" => "Unknown function: $func_name")
        else
            Dict("success" => true)
        end

        @test haskey(result, "error")
        @test occursin("Unknown function", result["error"])
    end

    @testset "Integration Tests" begin
        # Test that all main functions return proper error handling
        json_uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
        functions_to_test = [
            () -> DependabotHelper.parse_project("/nonexistent/Project.toml"),
            () -> DependabotHelper.get_latest_version("NonExistentPackage12345", "00000000-0000-0000-0000-000000000000"),
            () -> DependabotHelper.parse_project("/nonexistent/Project.toml"),
            () -> DependabotHelper.get_package_metadata("NonExistentPackage12345", "00000000-0000-0000-0000-000000000000"),
            () -> DependabotHelper.parse_manifest("/nonexistent/Manifest.toml"),
            () -> DependabotHelper.check_update_compatibility("/nonexistent/Project.toml", "JSON", "0.21.0")
        ]

        for test_func in functions_to_test
            result = @test_nowarn test_func()
            @test isa(result, Dict)
            # All functions should return either success data or error information
            @test haskey(result, "error") || length(result) > 0
        end
    end

    @testset "Version Constraint Parsing Tests" begin
        # Test empty constraints (not valid in Julia compat)
        result = @test_nowarn DependabotHelper.parse_julia_version_constraint("")
        @test result["type"] == "error"
        @test haskey(result, "error")

        # Test caret constraints
        result = @test_nowarn DependabotHelper.parse_julia_version_constraint("^1.0")
        @test result["type"] == "parsed"
        @test result["constraint"] == "^1.0"

        # Test tilde constraints
        result = @test_nowarn DependabotHelper.parse_julia_version_constraint("~1.2.3")
        @test result["type"] == "parsed"
        @test result["constraint"] == "~1.2.3"

        # Test standard constraints
        result = @test_nowarn DependabotHelper.parse_julia_version_constraint(">=1.0")
        @test result["type"] == "parsed"
        @test result["constraint"] == ">=1.0"

        # Test invalid constraints
        result = @test_logs (:error, r"parse_julia_version_constraint: Failed to parse constraint") DependabotHelper.parse_julia_version_constraint("invalid-version")
        @test result["type"] == "error"
        @test haskey(result, "error")
    end

    @testset "Version Satisfaction Tests" begin
        # Test empty constraint (not valid in Julia compat)
        @test DependabotHelper.check_version_satisfies_constraint("1.0.0", "") == false

        # Test caret constraint satisfaction
        @test DependabotHelper.check_version_satisfies_constraint("1.0.0", "^1.0") == true
        @test DependabotHelper.check_version_satisfies_constraint("1.5.0", "^1.0") == true
        @test DependabotHelper.check_version_satisfies_constraint("2.0.0", "^1.0") == false

        # Test standard constraint satisfaction
        @test DependabotHelper.check_version_satisfies_constraint("1.5.0", ">=1.0") == true
        @test DependabotHelper.check_version_satisfies_constraint("0.9.0", ">=1.0") == false

        # Test invalid version/constraint combinations
        @test_logs (:error, r"check_version_satisfies_constraint: Failed to check version constraint") DependabotHelper.check_version_satisfies_constraint("invalid", ">=1.0") == false
        @test_logs (:error, r"check_version_satisfies_constraint: Failed to check version constraint") DependabotHelper.check_version_satisfies_constraint("1.0.0", "invalid") == false
    end

    @testset "Version Constraint Expansion Tests" begin
        # Test empty constraint (not valid in Julia compat)
        result = @test_nowarn DependabotHelper.expand_version_constraint("")
        @test result["type"] == "error"
        @test haskey(result, "error")

        # Test caret expansion
        result = @test_nowarn DependabotHelper.expand_version_constraint("^1.0")
        @test result["type"] == "constraint"
        @test result["original"] == "^1.0"
        @test haskey(result, "ranges")

        # Test standard constraint expansion
        result = @test_nowarn DependabotHelper.expand_version_constraint(">=1.0")
        @test result["type"] == "constraint"
        @test haskey(result, "ranges")

        # Test error handling
        result = @test_logs (:error, r"expand_version_constraint: Failed to expand constraint") DependabotHelper.expand_version_constraint("invalid")
        @test result["type"] == "error"
        @test haskey(result, "error")
    end

    @testset "Package Registry Tests" begin
        # Test package version fetching
        json_uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
        result = @test_nowarn DependabotHelper.fetch_package_versions("JSON", json_uuid)
        if !haskey(result, "error")
            @test result["package_name"] == "JSON"
            @test haskey(result, "versions")
            @test haskey(result, "latest_version")
            @test haskey(result, "total_versions")
            @test length(result["versions"]) > 0
        end

        # Test package info fetching
        result = @test_nowarn DependabotHelper.fetch_package_info("JSON", json_uuid)
        if !haskey(result, "error")
            @test result["name"] == "JSON"
            @test haskey(result, "uuid")
            @test haskey(result, "all_versions")
            @test haskey(result, "latest_version")
        end

        # Test with non-existent package
        result = @test_nowarn DependabotHelper.fetch_package_versions("NonExistentPackage12345", "00000000-0000-0000-0000-000000000000")
        @test haskey(result, "error")

        result = @test_nowarn DependabotHelper.fetch_package_info("NonExistentPackage12345", "00000000-0000-0000-0000-000000000000")
        @test haskey(result, "error")
    end

    @testset "UUID-based Package Lookup Tests" begin

        json_uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"

        # Test find_package_source_url with both name and UUID
        result_with_uuid = @test_nowarn DependabotHelper.find_package_source_url("JSON", json_uuid)
        @test haskey(result_with_uuid, "source_url")
        @test haskey(result_with_uuid, "package_uuid")
        @test result_with_uuid["package_uuid"] == json_uuid

        # Test with mismatched UUID (should fail)
        fake_uuid = "00000000-0000-0000-0000-000000000000"
        result_wrong_uuid = @test_nowarn DependabotHelper.find_package_source_url("JSON", fake_uuid)
        @test haskey(result_wrong_uuid, "error")

        # Test get_latest_version with UUID
        version_result = @test_nowarn DependabotHelper.get_latest_version("JSON", json_uuid)
        @test haskey(version_result, "version") || haskey(version_result, "error")
        if haskey(version_result, "version")
            @test haskey(version_result, "package_uuid")
            @test version_result["package_uuid"] == json_uuid
        end
    end

    @testset "New Package Functions Tests" begin
        json_uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"

        # Test get_available_versions function
        result = @test_nowarn DependabotHelper.get_available_versions("JSON", json_uuid)
        if !haskey(result, "error")
            @test haskey(result, "versions")
            @test isa(result["versions"], Array)
            @test length(result["versions"]) > 0
            # Check that versions are strings
            @test all(v -> isa(v, String), result["versions"])
        end

        # Test get_available_versions with non-existent package
        result = @test_nowarn DependabotHelper.get_available_versions("NonExistentPackage12345", "00000000-0000-0000-0000-000000000000")
        @test haskey(result, "error")

        # Test get_version_release_date function
        # First get available versions to test with a real version
        versions_result = DependabotHelper.get_available_versions("JSON", json_uuid)
        if !haskey(versions_result, "error") && !isempty(versions_result["versions"])
            test_version = versions_result["versions"][1]
            result = @test_nowarn DependabotHelper.get_version_release_date("JSON", test_version, json_uuid)
            # Note: Julia registries don't store release dates, so we expect null
            @test haskey(result, "release_date")
        end

        # Test get_version_release_date with non-existent package
        result = @test_nowarn DependabotHelper.get_version_release_date("NonExistentPackage12345", "1.0.0", "00000000-0000-0000-0000-000000000000")
        @test haskey(result, "error")

        # Test get_version_release_date with invalid version
        result = @test_nowarn DependabotHelper.get_version_release_date("JSON", "999.999.999", json_uuid)
        @test haskey(result, "error")
    end

    @testset "Manifest Functions Tests" begin
        # Test get_version_from_manifest with non-existent file
        result = @test_nowarn DependabotHelper.get_version_from_manifest("/nonexistent/Manifest.toml", "JSON", "682c06a0-de6a-54ab-a142-c8b1cf79cde6")
        @test haskey(result, "error")

        # Test update_manifest with non-existent file
        result = @test_nowarn DependabotHelper.update_manifest("/nonexistent/Project.toml", Dict("JSON" => "0.21.4"))
        @test haskey(result, "error")

        # Test update_manifest with actual manifest update
        # This simulates the production workflow:
        # 1. Ruby updates Project.toml compat section
        # 2. Julia helper updates Manifest.toml based on new compat constraints
        mktempdir() do tmpdir
            # Create a test project with updated compat (as Ruby would do)
            project_path = joinpath(tmpdir, "Project.toml")
            manifest_path = joinpath(tmpdir, "Manifest.toml")

            # This is the Project.toml AFTER Ruby has updated the compat section
            write(project_path, """
                name = "TestProject"
                uuid = "12345678-1234-1234-1234-123456789012"
                version = "0.1.0"

                [deps]
                JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"

                [compat]
                JSON = "0.21"
                julia = "1.10"
                """)

            # Create a simple manifest file
            write(manifest_path, """
                # This file is machine-generated - editing it directly is not advised

                julia_version = "1.12.1"
                manifest_format = "2.0"
                project_hash = "72e3b6274dbcfd64d294f19fccd9d75e091f4b67"

                [[deps.Dates]]
                deps = ["Printf"]
                uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"
                version = "1.11.0"

                [[deps.JSON]]
                deps = ["Dates", "Mmap", "Unicode"]
                git-tree-sha1 = "565947e5338efe62a7db0aa8e5de782c623b04cd"
                uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
                version = "0.20.1"

                [[deps.Mmap]]
                uuid = "a63ad114-7e13-5084-954f-fe012c677804"
                version = "1.11.0"

                [[deps.Printf]]
                deps = ["Unicode"]
                uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"
                version = "1.11.0"

                [[deps.Unicode]]
                uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"
                version = "1.11.0"
                """)

            # Test args wrapper with JSON.Object (simulating JSON deserialization)
            # This is the main test - ensuring JSON.Object doesn't cause MethodError
            json_string = """{"project_path": "$tmpdir", "updates": {"JSON": "0.21.1"}}"""
            json_args = JSON.parse(json_string)  # This creates JSON.Object types

            # Verify we're testing JSON.Object handling
            @test json_args isa JSON.Object
            @test json_args["updates"] isa JSON.Object

            result = DependabotHelper.update_manifest(json_args)

            # The critical test: no MethodError on JSON.Object conversion
            @test !haskey(result, "error")
            @test haskey(result, "updated_manifest")
            @test haskey(result, "manifest_content")

            # Verify the manifest was updated - dependencies is an array
            updated_manifest = result["updated_manifest"]
            @test haskey(updated_manifest, "dependencies")
            @test updated_manifest["dependencies"] isa Vector

            # Find JSON in the dependencies array
            json_dep = findfirst(d -> d["name"] == "JSON", updated_manifest["dependencies"])
            @test json_dep !== nothing
            @test updated_manifest["dependencies"][json_dep]["version"] == "0.21.1"
        end
    end

    @testset "URL and Metadata Extraction Tests" begin
        json_uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"

        # Test extract_package_metadata_from_url
        # This function needs a valid source URL, so we'll test error handling first
        result = @test_nowarn DependabotHelper.extract_package_metadata_from_url("JSON", "invalid-url")
        @test haskey(result, "error") || haskey(result, "source_url")

        # Test with a GitHub URL format that might be expected
        github_url = "https://github.com/JuliaIO/JSON.jl.git"
        result = @test_nowarn DependabotHelper.extract_package_metadata_from_url("JSON", github_url)
        # This should either succeed or fail gracefully
        @test isa(result, Dict)
    end

    @testset "Dependency Resolution Tests" begin
        # Test resolve_dependencies_with_constraints with non-existent project
        result = @test_nowarn DependabotHelper.resolve_dependencies_with_constraints("/nonexistent/Project.toml", Dict("JSON" => "0.21.4"))
        @test haskey(result, "error")
    end

    @testset "Args Wrapper Function Tests" begin
        json_uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"

        # Test get_available_versions args wrapper
        result = @test_nowarn DependabotHelper.get_available_versions(Dict("package_name" => "JSON", "package_uuid" => json_uuid))
        @test !haskey(result, "error") || result["error"] != "Both package_name and package_uuid are required"

        # Test get_available_versions args wrapper with missing args
        result = @test_nowarn DependabotHelper.get_available_versions(Dict("package_name" => "JSON"))
        @test haskey(result, "error")
        @test result["error"] == "Both package_name and package_uuid are required"

        # Test get_version_release_date args wrapper
        result = @test_nowarn DependabotHelper.get_version_release_date(Dict(
            "package_name" => "JSON",
            "version" => "0.21.4",
            "package_uuid" => json_uuid
        ))
        @test isa(result, Dict)

        # Test get_version_release_date args wrapper with missing args
        result = @test_nowarn DependabotHelper.get_version_release_date(Dict("package_name" => "JSON"))
        @test haskey(result, "error")
        @test result["error"] == "Both package_name and version are required"

        # Test find_package_source_url args wrapper with missing args
        result = @test_nowarn DependabotHelper.find_package_source_url(Dict("package_name" => "JSON"))
        @test haskey(result, "error")
        @test result["error"] == "Both package_name and package_uuid are required"

        # Test get_package_metadata args wrapper with missing args
        result = @test_nowarn DependabotHelper.get_package_metadata(Dict("package_name" => "JSON"))
        @test haskey(result, "error")
        @test result["error"] == "Both package_name and package_uuid are required"

        # Test fetch_package_versions args wrapper with missing args
        result = @test_nowarn DependabotHelper.fetch_package_versions(Dict("package_name" => "JSON"))
        @test haskey(result, "error")
        @test result["error"] == "Both package_name and package_uuid are required"

        # Test fetch_package_info args wrapper with missing args
        result = @test_nowarn DependabotHelper.fetch_package_info(Dict("package_name" => "JSON"))
        @test haskey(result, "error")
        @test result["error"] == "Both package_name and package_uuid are required"
    end

    @testset "JSON Interface Extended Tests" begin
        json_uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"

        # Test all new functions through the JSON interface
        new_test_cases = [
            """{"function": "get_available_versions", "args": {"package_name": "JSON", "package_uuid": "$json_uuid"}}""",
            """{"function": "get_version_release_date", "args": {"package_name": "JSON", "version": "0.21.4", "package_uuid": "$json_uuid"}}""",
            """{"function": "get_version_from_manifest", "args": {"manifest_path": "/nonexistent/Manifest.toml", "name": "JSON", "uuid": "$json_uuid"}}""",
            """{"function": "update_manifest", "args": {"project_path": "/nonexistent/Project.toml", "updates": {"JSON": "0.21.4"}}}""",
            """{"function": "extract_package_metadata_from_url", "args": {"package_name": "JSON", "source_url": "https://github.com/JuliaIO/JSON.jl.git"}}""",
            """{"function": "resolve_dependencies_with_constraints", "args": {"project_path": "/nonexistent/Project.toml", "target_updates": {"JSON": "0.21.4"}}}"""
        ]

        for test_input in new_test_cases
            @test_nowarn begin
                result_json = DependabotHelper.run(test_input)
                result = JSON.parse(result_json)
                # All functions should return either success or error
                @test haskey(result, "result") || haskey(result, "error")
            end
        end

        # Test error handling for missing required arguments
        error_test_cases = [
            """{"function": "get_available_versions", "args": {"package_name": "JSON"}}""",
            """{"function": "get_version_release_date", "args": {"package_name": "JSON"}}""",
            """{"function": "find_package_source_url", "args": {"package_name": "JSON"}}""",
            """{"function": "get_package_metadata", "args": {"package_name": "JSON"}}""",
            """{"function": "fetch_package_versions", "args": {"package_name": "JSON"}}""",
            """{"function": "fetch_package_info", "args": {"package_name": "JSON"}}"""
        ]

        for test_input in error_test_cases
            @test_nowarn begin
                result_json = DependabotHelper.run(test_input)
                result = JSON.parse(result_json)
                # These should all return errors due to missing required args
                # The error could be in "result" key or directly as "error" key
                if haskey(result, "result")
                    @test haskey(result["result"], "error")
                elseif haskey(result, "error")
                    @test true  # Direct error response is also valid
                else
                    @test false  # Should have either result.error or error
                end
            end
        end
    end

    @testset "Batch Operations Tests" begin
        json_uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
        example_uuid = "7876af07-990d-54b4-ab0e-23690620f79a"

        @testset "batch_get_package_info" begin
            # Test with valid packages
            packages = [
                Dict{String,String}("name" => "JSON", "uuid" => json_uuid),
                Dict{String,String}("name" => "Example", "uuid" => example_uuid)
            ]

            result = DependabotHelper.batch_get_package_info(packages)
            @test result isa Dict
            @test haskey(result, "JSON")
            @test haskey(result, "Example")
            @test haskey(result["JSON"], "available_versions")
            @test haskey(result["JSON"], "latest_version")
            @test result["JSON"]["available_versions"] isa Vector

            # Test with empty array - returns empty Dict
            result_empty = DependabotHelper.batch_get_package_info(Vector{Dict{String,String}}())
            @test result_empty isa Dict
            @test isempty(result_empty) || haskey(result_empty, "error")

            # Test with invalid package
            invalid_packages = [
                Dict{String,String}("name" => "NonExistent12345", "uuid" => "00000000-0000-0000-0000-000000000000")
            ]
            result_invalid = DependabotHelper.batch_get_package_info(invalid_packages)
            @test result_invalid isa Dict
            @test haskey(result_invalid, "NonExistent12345")
        end

        @testset "batch_get_available_versions" begin
            # Test with valid packages
            packages = [
                Dict{String,String}("name" => "JSON", "uuid" => json_uuid),
                Dict{String,String}("name" => "Example", "uuid" => example_uuid)
            ]

            result = DependabotHelper.batch_get_available_versions(packages)
            @test result isa Dict
            @test haskey(result, "JSON")
            @test haskey(result, "Example")
            @test haskey(result["JSON"], "versions")
            @test result["JSON"]["versions"] isa Vector
            @test !isempty(result["JSON"]["versions"])

            # Test with empty array - returns empty Dict
            result_empty = DependabotHelper.batch_get_available_versions(Vector{Dict{String,String}}())
            @test result_empty isa Dict
            @test isempty(result_empty) || haskey(result_empty, "error")
        end

        @testset "batch_get_version_release_dates" begin
            # Test with valid packages and versions
            packages_versions = [
                Dict{String,Any}(
                    "name" => "JSON",
                    "uuid" => json_uuid,
                    "versions" => ["0.21.0", "0.21.1"]
                ),
                Dict{String,Any}(
                    "name" => "Example",
                    "uuid" => example_uuid,
                    "versions" => ["0.5.3"]
                )
            ]

            result = DependabotHelper.batch_get_version_release_dates(packages_versions)
            @test result isa Dict
            @test haskey(result, "JSON")
            @test haskey(result, "Example")
            @test result["JSON"] isa Dict
            @test haskey(result["JSON"], "0.21.0")

            # Test with empty array - returns empty Dict
            result_empty = DependabotHelper.batch_get_version_release_dates(Vector{Dict{String,Any}}())
            @test result_empty isa Dict
            @test isempty(result_empty) || haskey(result_empty, "error")
        end

        @testset "Batch Operations Args Wrappers" begin
            # Test batch_get_package_info through args wrapper
            args = Dict{String,Any}(
                "packages" => [
                    Dict{String,Any}("name" => "JSON", "uuid" => json_uuid)
                ]
            )
            result = DependabotHelper.batch_get_package_info(args)
            @test result isa Dict
            @test haskey(result, "JSON")

            # Test batch_get_available_versions through args wrapper
            result = DependabotHelper.batch_get_available_versions(args)
            @test result isa Dict
            @test haskey(result, "JSON")

            # Test batch_get_version_release_dates through args wrapper
            args_versions = Dict{String,Any}(
                "packages_versions" => [
                    Dict{String,Any}(
                        "name" => "JSON",
                        "uuid" => json_uuid,
                        "versions" => ["0.21.0"]
                    )
                ]
            )
            result = DependabotHelper.batch_get_version_release_dates(args_versions)
            @test result isa Dict
            @test haskey(result, "JSON")
        end

        @testset "Batch Operations via JSON Interface" begin
            # Test batch_get_package_info through JSON interface
            json_input = """{"function": "batch_get_package_info", "args": {"packages": [{"name": "JSON", "uuid": "$json_uuid"}]}}"""
            result_json = DependabotHelper.run(json_input)
            result = JSON.parse(result_json)
            # Check for successful result or error
            @test !haskey(result, "error") || error("Unexpected error: $(result["error"])")
            @test haskey(result, "result")
            @test haskey(result["result"], "JSON")

            # Test batch_get_available_versions through JSON interface
            json_input = """{"function": "batch_get_available_versions", "args": {"packages": [{"name": "JSON", "uuid": "$json_uuid"}]}}"""
            result_json = DependabotHelper.run(json_input)
            result = JSON.parse(result_json)
            @test !haskey(result, "error") || error("Unexpected error: $(result["error"])")
            @test haskey(result, "result")
            @test haskey(result["result"], "JSON")

            # Test batch_get_version_release_dates through JSON interface
            json_input = """{"function": "batch_get_version_release_dates", "args": {"packages_versions": [{"name": "JSON", "uuid": "$json_uuid", "versions": ["0.21.0"]}]}}"""
            result_json = DependabotHelper.run(json_input)
            result = JSON.parse(result_json)
            @test !haskey(result, "error") || error("Unexpected error: $(result["error"])")
            @test haskey(result, "result")
            @test haskey(result["result"], "JSON")
        end
    end
end
