using System.Text.Json;

using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core;

public record ExperimentsManager
{
    private const string UpdateFileBasedAppsExperimentName = "nuget_update_file_based_apps";

    public bool GenerateSimplePrBody { get; init; } = false;
    public bool FindRootDirectory { get; init; } = false;
    public bool UpdateFileBasedApps { get; init; } = true;

    public Dictionary<string, object> ToDictionary()
    {
        return new()
        {
            ["nuget_generate_simple_pr_body"] = GenerateSimplePrBody,
            ["nuget_find_root_directory"] = FindRootDirectory,
            [UpdateFileBasedAppsExperimentName] = UpdateFileBasedApps,
        };
    }

    public static ExperimentsManager GetExperimentsManager(Dictionary<string, object>? experiments)
    {
        return new ExperimentsManager()
        {
            GenerateSimplePrBody = IsEnabled(experiments, "nuget_generate_simple_pr_body"),
            FindRootDirectory = IsEnabled(experiments, "nuget_find_root_directory"),
            UpdateFileBasedApps = IsEnabled(experiments, UpdateFileBasedAppsExperimentName, defaultValue: true),
        };
    }

    public static ExperimentsManager FromJob(Job job)
    {
        var experimentsManager = GetExperimentsManager(job.Experiments);
        return experimentsManager with
        {
            UpdateFileBasedApps = job.UpdateFileBasedApps && experimentsManager.UpdateFileBasedApps,
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
            experimentsManager = FromJob(jobWrapper.Job);
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

    private static bool IsEnabled(Dictionary<string, object>? experiments, string experimentName, bool defaultValue = false)
    {
        if (experiments is null)
        {
            return defaultValue;
        }

        // prefer experiments named with underscores, but hyphens are also allowed as an alternate
        object? experimentValue;
        var experimentNameAlternate = experimentName.Replace("_", "-");
        if (experiments.TryGetValue(experimentName, out experimentValue) ||
            experiments.TryGetValue(experimentNameAlternate, out experimentValue))
        {
            var value = experimentValue?.ToString() ?? "";
            if (value.Equals("true", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }

            if (value.Equals("false", StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }
        }

        return defaultValue;
    }
}
