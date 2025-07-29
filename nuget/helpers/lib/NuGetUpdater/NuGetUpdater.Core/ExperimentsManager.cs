using System.Text.Json;

using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core;

public record ExperimentsManager
{
    public bool EnableCooldown { get; init; } = false;
    public bool GenerateSimplePrBody { get; init; } = false;
    public bool NativeUpdater { get; init; } = false;

    public Dictionary<string, object> ToDictionary()
    {
        return new()
        {
            ["enable_cooldown_for_nuget"] = EnableCooldown,
            ["nuget_generate_simple_pr_body"] = GenerateSimplePrBody,
            ["nuget_native_updater"] = NativeUpdater,
        };
    }

    public static ExperimentsManager GetExperimentsManager(Dictionary<string, object>? experiments)
    {
        return new ExperimentsManager()
        {
            EnableCooldown = IsEnabled(experiments, "enable_cooldown_for_nuget"),
            GenerateSimplePrBody = IsEnabled(experiments, "nuget_generate_simple_pr_body"),
            NativeUpdater = IsEnabled(experiments, "nuget_native_updater"),
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
