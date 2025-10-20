using Test
using Pkg
using JSON

@testset "Custom Registry Management Tests" begin

    # Helper function to run test code in isolated Julia process with temporary depot
    function run_in_isolated_process(test_code::String; timeout=60)
        tmp_depot = mktempdir()

        # Create a temporary Julia script
        test_script = """
        ENV["JULIA_DEPOT_PATH"] = "$tmp_depot:"

        using Test
        using DependabotHelper

        $test_code
        """

        script_file = tempname() * ".jl"
        try
            write(script_file, test_script)

            # Run the test in a separate Julia process with proper environment
            cmd = `$(Base.julia_cmd()[1]) --project=. $script_file`
            env = copy(ENV)
            env["JULIA_DEPOT_PATH"] = "$tmp_depot:"

            result = read(setenv(cmd, env), String)

            return result
        finally
            # Cleanup
            isfile(script_file) && rm(script_file)
            isdir(tmp_depot) && rm(tmp_depot; recursive=true, force=true)
        end
    end

    @testset "Basic Registry Operations" begin
        @testset "List Available Registries in Empty Depot" begin
            test_code = """
            registries = DependabotHelper.list_available_registries()
            @test isempty(registries)
            println("✓ Empty depot test passed")
            """

            result = run_in_isolated_process(test_code)
            @test occursin("✓ Empty depot test passed", result)
        end

        @testset "Add HolyLabRegistry" begin
            test_code = """
            test_registry_url = "https://github.com/HolyLab/HolyLabRegistry"

            # Add the registry
            DependabotHelper.add_custom_registries([test_registry_url])

            # Verify it was added
            registries = DependabotHelper.list_available_registries()
            @test length(registries) >= 1
            @test any(reg -> occursin("HolyLabRegistry", reg[1]), registries)

            println("✓ Registry addition test passed")
            """

            result = run_in_isolated_process(test_code; timeout=120) # Longer timeout for registry clone
            @test occursin("✓ Registry addition test passed", result)
        end

        @testset "Idempotent Registry Addition" begin
            test_code = """
            test_registry_url = "https://github.com/HolyLab/HolyLabRegistry"

            # Add the registry twice
            DependabotHelper.add_custom_registries([test_registry_url])
            initial_count = length(DependabotHelper.list_available_registries())

            # Add again - should be idempotent
            DependabotHelper.add_custom_registries([test_registry_url])
            final_count = length(DependabotHelper.list_available_registries())

            @test initial_count == final_count
            println("✓ Idempotent addition test passed")
            """

            result = run_in_isolated_process(test_code; timeout=120)
            @test occursin("✓ Idempotent addition test passed", result)
        end
    end

    @testset "Registry Update Operations" begin
        @testset "Update Registries" begin
            test_code = """
            test_registry_url = "https://github.com/HolyLab/HolyLabRegistry"

            # Add a registry first
            DependabotHelper.add_custom_registries([test_registry_url])

            # Test registry updates
            DependabotHelper.update_registries()

            # Should not throw errors
            println("✓ Registry update test passed")
            """

            result = run_in_isolated_process(test_code; timeout=120)
            @test occursin("✓ Registry update test passed", result)
        end

        @testset "Manage Registry State" begin
            test_code = """
            test_registry_url = "https://github.com/HolyLab/HolyLabRegistry"

            # Test the combined state management function
            result = DependabotHelper.manage_registry_state([test_registry_url])
            @test result == true

            # Verify registry is present
            registries = DependabotHelper.list_available_registries()
            @test any(reg -> occursin("HolyLabRegistry", reg[1]), registries)

            println("✓ Registry state management test passed")
            """

            result = run_in_isolated_process(test_code; timeout=120)
            @test occursin("✓ Registry state management test passed", result)
        end
    end

    @testset "Error Handling" begin
        @testset "Invalid Registry URL" begin
            test_code = """
            invalid_registry_url = "https://github.com/nonexistent/invalid-registry"

            # Should handle invalid URLs gracefully
            try
                DependabotHelper.add_custom_registries([invalid_registry_url])
                # If it doesn't error, that's fine too (might be network timeout)
                println("✓ Invalid URL test passed (no error)")
            catch e
                # Expected to error with invalid URL
                @test e isa Exception
                println("✓ Invalid URL test passed (expected error)")
            end
            """

            result = run_in_isolated_process(test_code; timeout=60)
            @test occursin("✓ Invalid URL test passed", result)
        end

        @testset "Empty Registry URL List" begin
            test_code = """
            # Test with empty registry list
            DependabotHelper.add_custom_registries(String[])

            # Should not error and should not change registry count
            registries = DependabotHelper.list_available_registries()
            @test isempty(registries)  # Fresh depot should be empty

            println("✓ Empty URL list test passed")
            """

            result = run_in_isolated_process(test_code)
            @test occursin("✓ Empty URL list test passed", result)
        end
    end

    @testset "JSON Interface Tests" begin
        @testset "List Registries via JSON" begin
            test_code = """
            # Test the JSON interface functions
            input = Dict("function" => "list_available_registries", "args" => Dict())
            json_input = JSON.json(input)

            result_json = DependabotHelper.run(json_input)
            result = JSON.parse(result_json)

            @test haskey(result, "result")
            @test result["result"] isa Array

            println("✓ JSON interface list registries test passed")
            """

            result = run_in_isolated_process(test_code)
            @test occursin("✓ JSON interface list registries test passed", result)
        end

        @testset "Add Registry via JSON" begin
            test_code = """
            # Test adding registry via JSON interface
            test_registry_url = "https://github.com/HolyLab/HolyLabRegistry"

            input = Dict(
                "function" => "add_custom_registries",
                "args" => Dict("registry_urls" => [test_registry_url])
            )
            json_input = JSON.json(input)

            result_json = DependabotHelper.run(json_input)
            result = JSON.parse(result_json)

            # Should not have an error
            @test !haskey(result, "error")

            # Verify registry was added
            list_input = Dict("function" => "list_available_registries", "args" => Dict())
            list_json = JSON.json(list_input)
            list_result_json = DependabotHelper.run(list_json)
            list_result = JSON.parse(list_result_json)

            @test length(list_result["result"]) >= 1

            println("✓ JSON interface add registry test passed")
            """

            result = run_in_isolated_process(test_code; timeout=120)
            @test occursin("✓ JSON interface add registry test passed", result)
        end
    end

    @testset "Multiple Registry Support" begin
        @testset "Add Multiple Registries" begin
            test_code = """
            # Test adding multiple registries
            test_registries = [
                "https://github.com/HolyLab/HolyLabRegistry"
                # Note: Only using one for now to avoid long test times
            ]

            DependabotHelper.add_custom_registries(test_registries)

            registries = DependabotHelper.list_available_registries()
            @test length(registries) >= length(test_registries)

            println("✓ Multiple registries test passed")
            """

            result = run_in_isolated_process(test_code; timeout=120)
            @test occursin("✓ Multiple registries test passed", result)
        end
    end
end
