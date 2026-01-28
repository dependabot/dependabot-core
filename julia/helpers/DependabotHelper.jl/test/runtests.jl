using Test
using JSON
using DependabotHelper

@testset "DependabotHelper.jl Tests" begin
    # Define UUIDs once for reuse throughout all tests
    json_uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
    example_uuid = "7876af07-990d-54b4-ab0e-23690620f79a"
    fake_uuid = "00000000-0000-0000-0000-000000000000"

    # Include custom registry management tests
    include("test_registry_management.jl")

    @testset "Function Tests" begin
        # Test error handling for non-existent files
        result = @test_nowarn DependabotHelper.parse_project("/nonexistent/Project.toml")
        @test haskey(result, "error")

        # Test get_latest_version with a known package
        result = @test_nowarn DependabotHelper.get_latest_version("JSON", json_uuid)
        @test haskey(result, "version")

        # Test get_latest_version with invalid package
        result = @test_nowarn DependabotHelper.get_latest_version("NonExistentPackage12345", "00000000-0000-0000-0000-000000000000")
        @test haskey(result, "error")

        # Test parsing with non-existent file
        result = @test_nowarn DependabotHelper.parse_project("/nonexistent/Project.toml")
        @test haskey(result, "error")

        # Test package metadata retrieval
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
        functions_to_test = [
            () -> DependabotHelper.parse_project("/nonexistent/Project.toml"),
            () -> DependabotHelper.get_latest_version("NonExistentPackage12345", "00000000-0000-0000-0000-000000000000"),
            () -> DependabotHelper.parse_project("/nonexistent/Project.toml"),
            () -> DependabotHelper.get_package_metadata("NonExistentPackage12345", "00000000-0000-0000-0000-000000000000"),
            () -> DependabotHelper.parse_manifest("/nonexistent/Manifest.toml"),
            () -> DependabotHelper.check_update_compatibility("/nonexistent/Project.toml", "JSON", "0.21.0", json_uuid)
        ]

        for test_func in functions_to_test
            result = @test_nowarn test_func()
            @test isa(result, Dict)
            # All functions should return either success data or error information
            @test haskey(result, "error") || length(result) > 0
        end
    end

    @testset "Environment File Detection Tests" begin
        # Test with a real environment that has Project.toml
        mktempdir() do tmpdir
            # Create a minimal Project.toml
            project_file = joinpath(tmpdir, "Project.toml")
            write(project_file, """
                name = "TestProject"
                uuid = "12345678-1234-1234-1234-123456789012"
                version = "0.1.0"
                """)

            # Create a minimal Manifest.toml
            manifest_file = joinpath(tmpdir, "Manifest.toml")
            write(manifest_file, """
                # This file is machine-generated
                julia_version = "1.10.0"
                manifest_format = "2.0"
                """)

            # Test find_environment_files
            found_project, found_manifest = DependabotHelper.find_environment_files(tmpdir)
            @test isfile(found_project)
            @test isfile(found_manifest)
            @test basename(found_project) == "Project.toml"
            @test basename(found_manifest) == "Manifest.toml"

            # Test helper functions
            @test DependabotHelper.get_project_file_name(tmpdir) == "Project.toml"
            @test DependabotHelper.get_manifest_file_name(tmpdir) == "Manifest.toml"
        end

        # Test find_environment_files when manifest doesn't exist
        @testset "find_environment_files without manifest" begin
            mktempdir() do tmpdir
                # Create only a Project.toml (no Manifest.toml)
                project_file = joinpath(tmpdir, "Project.toml")
                write(project_file, """
                    name = "TestPackage"
                    uuid = "12345678-1234-1234-1234-123456789abc"
                    version = "1.0.0"
                    """)

                # find_environment_files should still work and return a path for manifest
                # even if it doesn't exist yet (Pkg will create it when needed)
                found_project, found_manifest = DependabotHelper.find_environment_files(tmpdir)
                @test isfile(found_project)
                @test basename(found_project) == "Project.toml"

                # The manifest path is returned but the file doesn't exist yet
                @test basename(found_manifest) == "Manifest.toml"
                @test !isfile(found_manifest)  # Manifest doesn't exist yet
            end
        end

        # Test find_environment_files with workspace setup - WorkspaceOne (simple single member)
        @testset "find_environment_files with WorkspaceOne" begin
            # Use the static workspace test structure
            workspace_root = joinpath(@__DIR__, "WorkspaceOne")
            @test isdir(workspace_root)

            root_project = joinpath(workspace_root, "Project.toml")
            root_manifest = joinpath(workspace_root, "Manifest.toml")
            @test isfile(root_project)
            @test isfile(root_manifest)

            member_dir = joinpath(workspace_root, "SubPackage")
            member_project = joinpath(member_dir, "Project.toml")
            @test isdir(member_dir)
            @test isfile(member_project)

            # Note: Workspaces work for one directory deep (this test case)
            # Julia has a bug preventing deeper nesting (e.g., packages/core/SubPackage)
            # See: https://github.com/JuliaLang/julia/pull/59849

            # Test that find_environment_files correctly identifies the workspace manifest
            found_project, found_manifest = DependabotHelper.find_environment_files(member_dir)
            @test isfile(found_project)
            @test samefile(found_project, member_project)
            @test basename(found_project) == "Project.toml"

            # For one-level-deep workspaces, this should work correctly
            @test isfile(found_manifest)
            @test samefile(found_manifest, root_manifest)
        end

        # Test find_environment_files with workspace setup - WorkspaceTwo (multiple members with potential conflicts)
        @testset "find_environment_files with WorkspaceTwo" begin
            # WorkspaceTwo has SubPackageA and SubPackageB, both depending on JSON 0.21
            workspace_root = joinpath(@__DIR__, "WorkspaceTwo")
            @test isdir(workspace_root)

            root_project = joinpath(workspace_root, "Project.toml")
            root_manifest = joinpath(workspace_root, "Manifest.toml")
            @test isfile(root_project)
            @test isfile(root_manifest)

            # Test SubPackageA
            member_a_dir = joinpath(workspace_root, "SubPackageA")
            member_a_project = joinpath(member_a_dir, "Project.toml")
            @test isdir(member_a_dir)
            @test isfile(member_a_project)

            found_project_a, found_manifest_a = DependabotHelper.find_environment_files(member_a_dir)
            @test isfile(found_project_a)
            @test samefile(found_project_a, member_a_project)
            @test basename(found_project_a) == "Project.toml"
            @test isfile(found_manifest_a)
            @test samefile(found_manifest_a, root_manifest)

            # Test SubPackageB
            member_b_dir = joinpath(workspace_root, "SubPackageB")
            member_b_project = joinpath(member_b_dir, "Project.toml")
            @test isdir(member_b_dir)
            @test isfile(member_b_project)

            found_project_b, found_manifest_b = DependabotHelper.find_environment_files(member_b_dir)
            @test isfile(found_project_b)
            @test samefile(found_project_b, member_b_project)
            @test basename(found_project_b) == "Project.toml"
            @test isfile(found_manifest_b)
            @test samefile(found_manifest_b, root_manifest)

            # Both subpackages should share the same manifest
            @test samefile(found_manifest_a, found_manifest_b)
        end

        # Test JSON interface for find_environment_files
        @testset "find_environment_files via JSON interface" begin
            workspace_root = joinpath(@__DIR__, "WorkspaceOne")
            member_dir = joinpath(workspace_root, "SubPackage")

            input = Dict("function" => "find_environment_files", "args" => Dict("directory" => member_dir))
            result_json = DependabotHelper.run(JSON.json(input))
            result = JSON.parse(result_json)

            @test haskey(result, "result")
            @test haskey(result["result"], "project_file")
            @test haskey(result["result"], "manifest_file")
            @test endswith(result["result"]["project_file"], "SubPackage/Project.toml")
            @test endswith(result["result"]["manifest_file"], "WorkspaceOne/Manifest.toml")
        end

        # Test find_workspace_project_files function
        @testset "find_workspace_project_files with WorkspaceOne" begin
            workspace_root = joinpath(@__DIR__, "WorkspaceOne")

            # Call from the workspace root
            result = DependabotHelper.find_workspace_project_files(workspace_root)

            @test !haskey(result, "error")
            @test haskey(result, "project_files")
            @test haskey(result, "manifest_file")
            @test haskey(result, "workspace_root")

            project_files = result["project_files"]
            @test length(project_files) >= 2  # Root Project.toml + SubPackage/Project.toml

            # Verify that both the root and subpackage project files are found
            root_project_found = any(pf -> endswith(pf, "WorkspaceOne/Project.toml"), project_files)
            subpackage_project_found = any(pf -> endswith(pf, "SubPackage/Project.toml"), project_files)
            @test root_project_found
            @test subpackage_project_found

            # Verify manifest is found
            @test endswith(result["manifest_file"], "WorkspaceOne/Manifest.toml")
        end

        @testset "find_workspace_project_files with WorkspaceTwo" begin
            workspace_root = joinpath(@__DIR__, "WorkspaceTwo")

            result = DependabotHelper.find_workspace_project_files(workspace_root)

            @test !haskey(result, "error")
            @test haskey(result, "project_files")

            project_files = result["project_files"]
            @test length(project_files) >= 3  # Root + SubPackageA + SubPackageB

            # Verify all project files are found
            root_found = any(pf -> endswith(pf, "WorkspaceTwo/Project.toml"), project_files)
            pkg_a_found = any(pf -> endswith(pf, "SubPackageA/Project.toml"), project_files)
            pkg_b_found = any(pf -> endswith(pf, "SubPackageB/Project.toml"), project_files)
            @test root_found
            @test pkg_a_found
            @test pkg_b_found
        end

        @testset "find_workspace_project_files via JSON interface" begin
            workspace_root = joinpath(@__DIR__, "WorkspaceOne")

            input = Dict("function" => "find_workspace_project_files", "args" => Dict("directory" => workspace_root))
            result_json = DependabotHelper.run(JSON.json(input))
            result = JSON.parse(result_json)

            @test haskey(result, "result")
            @test haskey(result["result"], "project_files")
            @test haskey(result["result"], "manifest_file")
            @test haskey(result["result"], "workspace_root")

            project_files = result["result"]["project_files"]
            @test length(project_files) >= 2
        end
    end

    @testset "Workspace Conflict Detection Tests" begin
        # Test that WorkspaceTwo demonstrates the expected workspace behavior
        # where multiple subpackages share a manifest but may have conflicting requirements
        @testset "WorkspaceTwo structure verification" begin
            workspace_root = joinpath(@__DIR__, "WorkspaceTwo")

            # Verify root structure
            @test isdir(workspace_root)
            @test isfile(joinpath(workspace_root, "Project.toml"))
            @test isfile(joinpath(workspace_root, "Manifest.toml"))

            # Verify SubPackageA
            subpkg_a = joinpath(workspace_root, "SubPackageA")
            @test isdir(subpkg_a)
            @test isfile(joinpath(subpkg_a, "Project.toml"))

            # Verify SubPackageB
            subpkg_b = joinpath(workspace_root, "SubPackageB")
            @test isdir(subpkg_b)
            @test isfile(joinpath(subpkg_b, "Project.toml"))

            # Parse the project files to verify dependencies
            result_a = DependabotHelper.parse_project(joinpath(subpkg_a, "Project.toml"))
            @test !haskey(result_a, "error")
            @test haskey(result_a, "dependencies")
            @test isa(result_a["dependencies"], Array)

            # Find JSON dependency in the array
            json_dep_a = findfirst(d -> d["name"] == "JSON", result_a["dependencies"])
            @test !isnothing(json_dep_a)
            @test result_a["dependencies"][json_dep_a]["uuid"] == "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
            @test haskey(result_a["dependencies"][json_dep_a], "requirement")
            @test result_a["dependencies"][json_dep_a]["requirement"] == "0.21"

            result_b = DependabotHelper.parse_project(joinpath(subpkg_b, "Project.toml"))
            @test !haskey(result_b, "error")
            @test haskey(result_b, "dependencies")
            @test isa(result_b["dependencies"], Array)

            # Find JSON and Dates dependencies
            json_dep_b = findfirst(d -> d["name"] == "JSON", result_b["dependencies"])
            @test !isnothing(json_dep_b)
            dates_dep_b = findfirst(d -> d["name"] == "Dates", result_b["dependencies"])
            @test !isnothing(dates_dep_b)

            # Both should have the same JSON compat requirement (0.21)
            @test haskey(result_b["dependencies"][json_dep_b], "requirement")
            @test result_b["dependencies"][json_dep_b]["requirement"] == "0.21"
        end

        @testset "WorkspaceTwo manifest resolution" begin
            workspace_root = joinpath(@__DIR__, "WorkspaceTwo")

            # Test that both subpackages correctly identify the shared manifest
            subpkg_a_dir = joinpath(workspace_root, "SubPackageA")
            subpkg_b_dir = joinpath(workspace_root, "SubPackageB")
            root_manifest = joinpath(workspace_root, "Manifest.toml")

            # Both should find the same shared manifest
            proj_a, manifest_a = DependabotHelper.find_environment_files(subpkg_a_dir)
            @test isfile(manifest_a)
            @test samefile(manifest_a, root_manifest)

            proj_b, manifest_b = DependabotHelper.find_environment_files(subpkg_b_dir)
            @test isfile(manifest_b)
            @test samefile(manifest_b, root_manifest)

            # They should be the exact same file
            @test samefile(manifest_a, manifest_b)
        end

        @testset "WorkspaceTwo update simulation" begin
            # This test simulates what happens when trying to update one workspace member
            # when workspace members have conflicting compat requirements

            workspace_root = joinpath(@__DIR__, "WorkspaceTwo")

            mktempdir() do tmpdir
                # Copy the workspace structure to a temp dir for testing
                tmp_workspace = joinpath(tmpdir, "WorkspaceTwo")
                cp(workspace_root, tmp_workspace)

                tmp_subpkg_a = joinpath(tmp_workspace, "SubPackageA")
                tmp_subpkg_b = joinpath(tmp_workspace, "SubPackageB")

                # Step 1: Update SubPackageA compat to allow both 0.21 and 1.x
                subpkg_a_project = joinpath(tmp_subpkg_a, "Project.toml")
                project_a_content = read(subpkg_a_project, String)
                project_a_content = replace(project_a_content, "JSON = \"0.21\"" => "JSON = \"0.21, 1\"")
                write(subpkg_a_project, project_a_content)

                # Step 2: Try to update manifest to JSON 1.0.0 from SubPackageA
                # This should FAIL because SubPackageB still only allows 0.21
                result = DependabotHelper.update_manifest(
                    tmp_subpkg_a,
                    Dict{String, Any}(json_uuid => Dict("name" => "JSON", "version" => "1.0.0"))
                )

                # Step 3: Verify we get an "Uempty intersection between" error
                @test isa(result, Dict)
                @test haskey(result, "error")
                @test occursin("empty intersection between", result["error"])

                # Step 4: Update SubPackageB compat to also allow 0.21 and 1.x
                subpkg_b_project = joinpath(tmp_subpkg_b, "Project.toml")
                project_b_content = read(subpkg_b_project, String)
                project_b_content = replace(project_b_content, "JSON = \"0.21\"" => "JSON = \"0.21, 1\"")
                write(subpkg_b_project, project_b_content)

                # Step 5: Try to update manifest to JSON 1.0.0 again
                # Now this should SUCCEED because both packages allow 1.x
                result = DependabotHelper.update_manifest(
                    tmp_subpkg_a,
                    Dict{String, Any}(json_uuid => Dict("name" => "JSON", "version" => "1.0.0"))
                )

                # Step 6: Verify the update succeeded (no "empty intersection between" error)
                @test isa(result, Dict)
                @test !haskey(result, "error")
                @test haskey(result, "updated_manifest")
                @test haskey(result, "manifest_content")

                # Verify JSON is present in the dependencies
                updated_manifest = result["updated_manifest"]
                @test haskey(updated_manifest, "dependencies")
                json_dep = findfirst(d -> d["name"] == "JSON", updated_manifest["dependencies"])
                @test json_dep !== nothing
            end
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

        # Test find_package_source_url with both name and UUID
        result_with_uuid = @test_nowarn DependabotHelper.find_package_source_url("JSON", json_uuid)
        @test haskey(result_with_uuid, "source_url")
        @test haskey(result_with_uuid, "package_uuid")
        @test result_with_uuid["package_uuid"] == json_uuid

        # Test with mismatched UUID (should fail)
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

        # Test get_version_release_date function with General registry package
        # JSON.jl is in the General registry, so it should return a real date
        versions_result = DependabotHelper.get_available_versions("JSON", json_uuid)
        test_version = "1.2.0"
        result = @test_nowarn DependabotHelper.get_version_release_date("JSON", test_version, json_uuid)
        @test result["release_date"] == "2025-10-17T01:08:11"

        # Test get_version_release_date with non-existent package
        result = @test_nowarn DependabotHelper.get_version_release_date("NonExistentPackage12345", "1.0.0", "00000000-0000-0000-0000-000000000000")
        @test haskey(result, "error")

        # Test get_version_release_date with invalid version
        result = @test_nowarn DependabotHelper.get_version_release_date("JSON", "999.999.999", json_uuid)
        @test haskey(result, "error")

        # Test helper functions for General registry
        @testset "General Registry Helper Functions" begin
            # Test is_package_in_general_registry with JSON (should be true)
            @test DependabotHelper.is_package_in_general_registry("JSON", json_uuid) == true

            # Test is_package_in_general_registry with non-existent package
            @test DependabotHelper.is_package_in_general_registry("NonExistentPackage12345", "00000000-0000-0000-0000-000000000000") == false

            # Test fetch_general_registry_release_date with a known version
            release_date = DependabotHelper.fetch_general_registry_release_date("JSON", test_version)
            @test release_date == "2025-10-17T01:08:11"
        end
    end

    @testset "Manifest Functions Tests" begin
        # Test get_version_from_manifest with non-existent file
        result = @test_nowarn DependabotHelper.get_version_from_manifest("/nonexistent/Manifest.toml", "JSON", "682c06a0-de6a-54ab-a142-c8b1cf79cde6")
        @test haskey(result, "error")

        # Test update_manifest with non-existent file
        result = @test_nowarn DependabotHelper.update_manifest("/nonexistent/Project.toml", Dict(json_uuid => Dict("name" => "JSON", "version" => "0.21.4")))
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
            json_string = """{"project_path": "$tmpdir", "updates": {"$json_uuid": {"name": "JSON", "version": "0.21.1"}}}"""
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
        result = @test_nowarn DependabotHelper.resolve_dependencies_with_constraints("/nonexistent/Project.toml", Dict(json_uuid => Dict("name" => "JSON", "version" => "0.21.4")))
        @test haskey(result, "error")
    end

    @testset "Args Wrapper Function Tests" begin

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
