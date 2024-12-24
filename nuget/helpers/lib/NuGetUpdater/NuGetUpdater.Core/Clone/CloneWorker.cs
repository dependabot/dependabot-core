using System.Net;

using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;

using CommandArguments = (string[] Args, string? WorkingDirectory);

namespace NuGetUpdater.Core.Clone;

public class CloneWorker
{
    private readonly string _jobId;
    private readonly IApiHandler _apiHandler;
    private readonly IGitCommandHandler _gitCommandHandler;

    public CloneWorker(string jobId, IApiHandler apiHandler, IGitCommandHandler gitCommandHandler)
    {
        _jobId = jobId;
        _apiHandler = apiHandler;
        _gitCommandHandler = gitCommandHandler;
    }

    // entrypoint for cli
    public async Task<int> RunAsync(FileInfo jobFilePath, DirectoryInfo repoContentsPath)
    {
        var jobFileContent = await File.ReadAllTextAsync(jobFilePath.FullName);

        // only a limited set of errors can occur here
        JobFile? jobFile = null;
        JobErrorBase? parseError = null;
        try
        {
            jobFile = RunWorker.Deserialize(jobFileContent);
        }
        catch (BadRequirementException ex)
        {
            parseError = new BadRequirement(ex.Message);
        }
        catch (Exception ex)
        {
            parseError = new UnknownError(ex, _jobId);
        }

        if (parseError is not null)
        {
            await ReportError(parseError);
            return 1;
        }

        var result = await RunAsync(jobFile!.Job, repoContentsPath.FullName);
        return result;
    }

    // object model entry point
    public async Task<int> RunAsync(Job job, string repoContentsPath)
    {
        JobErrorBase? error = null;
        try
        {
            var commandArgs = GetAllCommandArgs(job, repoContentsPath);
            foreach (var (args, workingDirectory) in commandArgs)
            {
                await _gitCommandHandler.RunGitCommandAsync(args, workingDirectory);
            }
        }
        catch (HttpRequestException ex)
        when (ex.StatusCode == HttpStatusCode.Unauthorized || ex.StatusCode == HttpStatusCode.Forbidden)
        {
            error = new JobRepoNotFound(ex.Message);
        }
        catch (Exception ex)
        {
            error = new UnknownError(ex, _jobId);
        }

        if (error is not null)
        {
            await ReportError(error);
            return 1;
        }

        return 0;
    }

    private async Task ReportError(JobErrorBase error)
    {
        await _apiHandler.RecordUpdateJobError(error);
        await _apiHandler.MarkAsProcessed(new("unknown"));
    }

    internal static CommandArguments[] GetAllCommandArgs(Job job, string repoContentsPath)
    {
        var commandArgs = new List<CommandArguments>()
        {
            GetCloneArgs(job, repoContentsPath)
        };

        if (job.Source.Commit is { } commit)
        {
            commandArgs.Add(GetFetchArgs(commit, repoContentsPath));
            commandArgs.Add(GetResetArgs(commit, repoContentsPath));
        }

        return commandArgs.ToArray();
    }

    internal static CommandArguments GetCloneArgs(Job job, string repoContentsPath)
    {
        var url = GetRepoUrl(job);
        var args = new List<string>()
        {
            "clone",
            "--no-tags",
            "--depth",
            "1",
            "--recurse-submodules",
            "--shallow-submodules",
        };

        if (job.Source.Branch is { } branch)
        {
            args.Add("--branch");
            args.Add(branch);
            args.Add("--single-branch");
        }

        args.Add(url);
        args.Add(repoContentsPath);
        return (args.ToArray(), null);
    }

    internal static CommandArguments GetFetchArgs(string commit, string repoContentsPath)
    {
        return
        (
            [
                "fetch",
                "--depth",
                "1",
                "--recurse-submodules=on-demand",
                "origin",
                commit
            ],
            repoContentsPath
        );
    }

    internal static CommandArguments GetResetArgs(string commit, string repoContentsPath)
    {
        return
        (
            [
                "reset",
                "--hard",
                "--recurse-submodules",
                commit
            ],
            repoContentsPath
        );
    }

    private static string GetRepoUrl(Job job)
    {
        return job.Source.Provider switch
        {
            "azure" => $"https://dev.azure.com/{job.Source.Repo}",
            "github" => $"https://github.com/{job.Source.Repo}",
            _ => throw new ArgumentException($"Unknown provider: {job.Source.Provider}")
        };
    }
}
