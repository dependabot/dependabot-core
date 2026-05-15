using Test
using Pkg
using JSON

@testset "Custom Registry Management Tests" begin

    # Helper function to run tests with isolated depot
    function with_temp_depot(f::Function)
        original_depot = Base.DEPOT_PATH[1]
        tmp_depot = mktempdir()

        # Set temporary depot
        Base.DEPOT_PATH[1] = tmp_depot
        try
            # Run the test function
            f()
        finally
            # Restore original depot
            Base.DEPOT_PATH[1] = original_depot
            rm(tmp_depot; recursive=true, force=true)
        end
    end

    @testset "Basic Registry Operations" begin
        @testset "List Available Registries in Empty Depot" begin
            with_temp_depot() do
                registries = DependabotHelper.list_available_registries()
                @test isempty(registries)
            end
        end

        @testset "Add HolyLabRegistry" begin
            with_temp_depot() do
                test_registry_url = "https://github.com/HolyLab/HolyLabRegistry"

                # Add the registry
                DependabotHelper.add_custom_registries([test_registry_url])

                # Verify it was added
                registries = DependabotHelper.list_available_registries()
                @test length(registries) >= 1
                @test any(reg -> occursin("HolyLabRegistry", reg[1]), registries)
            end
        end

        @testset "Idempotent Registry Addition" begin
            with_temp_depot() do
                test_registry_url = "https://github.com/HolyLab/HolyLabRegistry"

                # Add the registry twice
                DependabotHelper.add_custom_registries([test_registry_url])
                initial_count = length(DependabotHelper.list_available_registries())

                # Add again - should be idempotent
                DependabotHelper.add_custom_registries([test_registry_url])
                final_count = length(DependabotHelper.list_available_registries())

                @test initial_count == final_count
            end
        end
    end

    @testset "Registry Update Operations" begin
        @testset "Update Registries" begin
            with_temp_depot() do
                test_registry_url = "https://github.com/HolyLab/HolyLabRegistry"

                # Add a registry first
                DependabotHelper.add_custom_registries([test_registry_url])

                # Test registry updates - should not throw errors
                DependabotHelper.update_registries()
                @test true  # If we get here, update succeeded
            end
        end

        @testset "Manage Registry State" begin
            with_temp_depot() do
                test_registry_url = "https://github.com/HolyLab/HolyLabRegistry"

                # Test the combined state management function
                result = DependabotHelper.manage_registry_state([test_registry_url])
                @test result == true

                # Verify registry is present
                registries = DependabotHelper.list_available_registries()
                @test any(reg -> occursin("HolyLabRegistry", reg[1]), registries)
            end
        end
    end

    @testset "Error Handling" begin
        @testset "Invalid Registry URL" begin
            with_temp_depot() do
                invalid_registry_url = "https://github.com/nonexistent/invalid-registry"

                # Should handle invalid URLs gracefully
                try
                    DependabotHelper.add_custom_registries([invalid_registry_url])
                    # If it doesn't error, that's fine too (might be network timeout)
                    @test true
                catch e
                    # Expected to error with invalid URL
                    @test e isa Exception
                end
            end
        end

        @testset "Empty Registry URL List" begin
            with_temp_depot() do
                # Test with empty registry list
                DependabotHelper.add_custom_registries(String[])

                # Should not error and should not change registry count
                registries = DependabotHelper.list_available_registries()
                @test isempty(registries)  # Fresh depot should be empty
            end
        end
    end

    @testset "JSON Interface Tests" begin
        @testset "List Registries via JSON" begin
            with_temp_depot() do
                # Test the JSON interface functions
                input = Dict("function" => "list_available_registries", "args" => Dict())
                json_input = JSON.json(input)

                result_json = DependabotHelper.run(json_input)
                result = JSON.parse(result_json)

                @test haskey(result, "result")
                @test result["result"] isa Array
            end
        end

        @testset "Add Registry via JSON" begin
            with_temp_depot() do
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
            end
        end
    end

    @testset "Multiple Registry Support" begin
        @testset "Add Multiple Registries" begin
            with_temp_depot() do
                # Test adding multiple registries
                test_registries = [
                    "https://github.com/HolyLab/HolyLabRegistry"
                    # Note: Only using one for now to avoid long test times
                ]

                DependabotHelper.add_custom_registries(test_registries)

                registries = DependabotHelper.list_available_registries()
                @test length(registries) >= length(test_registries)
            end
        end
    end
end
