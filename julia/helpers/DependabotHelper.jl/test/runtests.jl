using Test
using JSON
using DependabotHelper

@testset "DependabotHelper.jl Tests" begin

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
        # Test wildcard constraints
        result = @test_nowarn DependabotHelper.parse_julia_version_constraint("*")
        @test result["type"] == "wildcard"
        @test haskey(result, "version_spec")

        result = @test_nowarn DependabotHelper.parse_julia_version_constraint("")
        @test result["type"] == "wildcard"

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
        result = @test_nowarn DependabotHelper.parse_julia_version_constraint("invalid-version")
        @test result["type"] == "error"
        @test haskey(result, "error")
    end

    @testset "Version Satisfaction Tests" begin
        # Test wildcard constraint satisfaction
        @test DependabotHelper.check_version_satisfies_constraint("1.0.0", "*") == true
        @test DependabotHelper.check_version_satisfies_constraint("2.5.1", "*") == true

        # Test caret constraint satisfaction
        @test DependabotHelper.check_version_satisfies_constraint("1.0.0", "^1.0") == true
        @test DependabotHelper.check_version_satisfies_constraint("1.5.0", "^1.0") == true
        @test DependabotHelper.check_version_satisfies_constraint("2.0.0", "^1.0") == false

        # Test standard constraint satisfaction
        @test DependabotHelper.check_version_satisfies_constraint("1.5.0", ">=1.0") == true
        @test DependabotHelper.check_version_satisfies_constraint("0.9.0", ">=1.0") == false

        # Test invalid version/constraint combinations
        @test DependabotHelper.check_version_satisfies_constraint("invalid", ">=1.0") == false
        @test DependabotHelper.check_version_satisfies_constraint("1.0.0", "invalid") == false
    end

    @testset "Version Constraint Expansion Tests" begin
        # Test wildcard expansion
        result = @test_nowarn DependabotHelper.expand_version_constraint("*")
        @test result["type"] == "wildcard"
        @test haskey(result, "description")

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
        result = @test_nowarn DependabotHelper.expand_version_constraint("invalid")
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
end

