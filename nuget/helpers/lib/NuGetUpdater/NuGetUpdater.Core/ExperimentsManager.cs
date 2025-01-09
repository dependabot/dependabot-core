using System.Text.Json;

using NuGetUpdater.Core.Run;

namespace NuGetUpdater.Core;

public record ExperimentsManager
{
    public bool InstallDotnetSdks { get; init; } = false;
    public bool UseLegacyDependencySolver { get; init; } = false;
    public bool UseDirectDiscovery { get; init; } = false;

    public Dictionary<string, object> ToDictionary()
    {
        return new()
        {
            ["nuget_install_dotnet_sdks"] = InstallDotnetSdks,
            ["nuget_legacy_dependency_solver"] = UseLegacyDependencySolver,
            ["nuget_use_direct_discovery"] = UseDirectDiscovery,
        };
    }

    public static ExperimentsManager GetExperimentsManager(Dictionary<string, object>? experiments)
    {
        return new ExperimentsManager()
        {
            InstallDotnetSdks = IsEnabled(experiments, "nuget_install_dotnet_sdks"),
            UseLegacyDependencySolver = IsEnabled(experiments, "nuget_legacy_dependency_solver"),
            UseDirectDiscovery = IsEnabled(experiments, "nuget_use_direct_discovery"),
        };
    }

    public static async Task<(ExperimentsManager ExperimentsManager, NativeResult? ErrorResult)> FromJobFileAsync(string jobFilePath)
    {
        var experimentsManager = new ExperimentsManager();
        NativeResult? errorResult = null;
        try
        {
            var jobFileContent = await File.ReadAllTextAsync(jobFilePath);
            var jobWrapper = RunWorker.Deserialize(jobFileContent);
            experimentsManager = GetExperimentsManager(jobWrapper.Job.Experiments);
        }
        catch (BadRequirementException ex)
        {
            errorResult = new NativeResult
            {
                ErrorType = ErrorType.BadRequirement,
                ErrorDetails = ex.Message,
            };
        }
        catch (JsonException ex)
        {
            errorResult = new NativeResult
            {
                ErrorType = ErrorType.Unknown,
                ErrorDetails = $"Error deserializing job file: {ex}: {File.ReadAllText(jobFilePath)}",
            };
        }
        catch (Exception ex)
        {
            errorResult = new NativeResult
            {
                ErrorType = ErrorType.Unknown,
                ErrorDetails = ex.ToString(),
            };
        }

        return (experimentsManager, errorResult);
    }

    private static bool IsEnabled(Dictionary<string, object>? experiments, string experimentName)
    {
        if (experiments is null)
        {
            return false;
        }

        if (experiments.TryGetValue(experimentName, out var value))
        {
            if ((value?.ToString() ?? "").Equals("true", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }
}
