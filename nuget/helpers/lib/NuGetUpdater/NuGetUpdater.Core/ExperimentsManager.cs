using System.Text.Json;

using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core;

public record ExperimentsManager
{
    public bool InstallDotnetSdks { get; init; } = false;
    public bool NativeUpdater { get; init; } = false;
    public bool UseLegacyDependencySolver { get; init; } = false;
    public bool UseLegacyUpdateHandler { get; init; } = false;
    public bool UseDirectDiscovery { get; init; } = false;
    public bool UseNewFileUpdater { get; init; } = false;

    public Dictionary<string, object> ToDictionary()
    {
        return new()
        {
            ["nuget_install_dotnet_sdks"] = InstallDotnetSdks,
            ["nuget_native_updater"] = NativeUpdater,
            ["nuget_legacy_dependency_solver"] = UseLegacyDependencySolver,
            ["nuget_use_legacy_update_handler"] = UseLegacyUpdateHandler,
            ["nuget_use_direct_discovery"] = UseDirectDiscovery,
            ["nuget_use_new_file_updater"] = UseNewFileUpdater,
        };
    }

    public static ExperimentsManager GetExperimentsManager(Dictionary<string, object>? experiments)
    {
        return new ExperimentsManager()
        {
            InstallDotnetSdks = IsEnabled(experiments, "nuget_install_dotnet_sdks"),
            NativeUpdater = IsEnabled(experiments, "nuget_native_updater"),
            UseLegacyDependencySolver = IsEnabled(experiments, "nuget_legacy_dependency_solver"),
            UseLegacyUpdateHandler = IsEnabled(experiments, "nuget_use_legacy_update_handler"),
            UseDirectDiscovery = IsEnabled(experiments, "nuget_use_direct_discovery"),
            UseNewFileUpdater = IsEnabled(experiments, "nuget_use_new_file_updater"),
        };
    }

    public static async Task<(ExperimentsManager ExperimentsManager, JobErrorBase? Error)> FromJobFileAsync(string jobId, string jobFilePath)
    {
        var experimentsManager = new ExperimentsManager();
        JobErrorBase? error = null;
        var jobFileContent = string.Empty;
        try
        {
            jobFileContent = await File.ReadAllTextAsync(jobFilePath);
            var jobWrapper = RunWorker.Deserialize(jobFileContent);
            experimentsManager = GetExperimentsManager(jobWrapper.Job.Experiments);
        }
        catch (JsonException ex)
        {
            // this is a very specific case where we want to log the JSON contents for easier debugging
            error = JobErrorBase.ErrorFromException(new NotSupportedException($"Error deserializing job file contents: {jobFileContent}", ex), jobId, Environment.CurrentDirectory); // TODO
        }
        catch (Exception ex)
        {
            error = JobErrorBase.ErrorFromException(ex, jobId, Environment.CurrentDirectory); // TODO
        }

        return (experimentsManager, error);
    }

    private static bool IsEnabled(Dictionary<string, object>? experiments, string experimentName)
    {
        if (experiments is null)
        {
            return false;
        }

        // prefer experiments named with underscores, but hyphens are also allowed as an alternate
        object? experimentValue;
        var experimentNameAlternate = experimentName.Replace("_", "-");
        if (experiments.TryGetValue(experimentName, out experimentValue) ||
            experiments.TryGetValue(experimentNameAlternate, out experimentValue))
        {
            if ((experimentValue?.ToString() ?? "").Equals("true", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }
}
