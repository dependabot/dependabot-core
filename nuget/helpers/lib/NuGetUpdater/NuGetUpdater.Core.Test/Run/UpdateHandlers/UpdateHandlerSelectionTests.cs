using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Run.UpdateHandlers;
using NuGetUpdater.Core.Run;
using Xunit;

namespace NuGetUpdater.Core.Test.Run.UpdateHandlers;

public class UpdateHandlerSelectionTests : UpdateHandlersTestsBase
{
    [Theory]
    [MemberData(nameof(GetUpdateHandlerFromJobTestData))]
    public void GetUpdateHandlerFromJob(Job job, IUpdateHandler expectedUpdateHandler)
    {
        var actualUpdateHandler = RunWorker.GetUpdateHandler(job);
        Assert.Equal(expectedUpdateHandler.GetType(), actualUpdateHandler.GetType());
    }

    public static IEnumerable<object[]> GetUpdateHandlerFromJobTestData()
    {
        // to ensure we're not depending on any default values, _ALWAYS_ set the following properties explicitly:
        //   Source
        //   Dependencies
        //   DependencyGroups
        //   DependencyGroupToRefresh
        //   SecurityUpdatesOnly
        //   UpdatingAPullRequest

        //
        // group_update_all_versions
        //
        yield return
        [
            new Job()
            {
                Source = CreateJobSource("/"),
                Dependencies = [],
                DependencyGroups = [],
                DependencyGroupToRefresh = null,
                SecurityUpdatesOnly = false,
                UpdatingAPullRequest = false,
            },
            GroupUpdateAllVersionsHandler.Instance,
        ];

        yield return
        [
            new Job()
            {
                Source = CreateJobSource("/"),
                Dependencies = ["Dependency.A", "Dependency.B"],
                DependencyGroups = [],
                DependencyGroupToRefresh = null,
                SecurityUpdatesOnly = true,
                UpdatingAPullRequest = false,
            },
            GroupUpdateAllVersionsHandler.Instance,
        ];

        yield return
        [
            new Job()
            {
                Source = CreateJobSource("/"),
                Dependencies = [],
                DependencyGroups = [new() { Name = "some-group", AppliesTo = "security-updates" }],
                DependencyGroupToRefresh = null,
                SecurityUpdatesOnly = true,
                UpdatingAPullRequest = false,
            },
            GroupUpdateAllVersionsHandler.Instance,
        ];

        //
        // update_version_group_pr
        //
        yield return
        [
            new Job()
            {
                Source = CreateJobSource("/dir1", "/dir2"),
                Dependencies = ["Some.Dependency"],
                DependencyGroups = [new() { Name = "some-group", AppliesTo = "security-updates" }], // this
                DependencyGroupToRefresh = "some-group",
                SecurityUpdatesOnly = false,
                UpdatingAPullRequest = true,
            },
            RefreshGroupUpdatePullRequestHandler.Instance,
        ];

        yield return
        [
            new Job()
            {
                Source = CreateJobSource("/src"),
                Dependencies = ["Dependency.A", "Dependency.B"],
                DependencyGroups = [new() { Name = "some-group", AppliesTo = "security-updates" }], // this
                DependencyGroupToRefresh = "some-group",
                SecurityUpdatesOnly = true,
                UpdatingAPullRequest = true,
            },
            RefreshGroupUpdatePullRequestHandler.Instance,
        ];

        yield return
        [
            new Job()
            {
                Source = CreateJobSource("/src"),
                Dependencies = ["Some.Dependency"],
                DependencyGroups = [new() { Name = "some-group", AppliesTo = "security-updates" }],
                DependencyGroupToRefresh = "some-group",
                SecurityUpdatesOnly = true,
                UpdatingAPullRequest = true,
            },
            RefreshGroupUpdatePullRequestHandler.Instance,
        ];

        yield return
        [
            new Job()
            {
                Source = CreateJobSource("/src"),
                Dependencies = ["Some.Dependency"],
                DependencyGroups = [new() { Name = "some-group", AppliesTo = "security-updates" }],
                DependencyGroupToRefresh = "some-group",
                SecurityUpdatesOnly = true,
                UpdatingAPullRequest = true,
            },
            RefreshGroupUpdatePullRequestHandler.Instance,
        ];

        //
        // create_security_pr
        //
        yield return
        [
            new Job()
            {
                Source = CreateJobSource("/src"),
                Dependencies = ["Some.Dependency"],
                DependencyGroups = [],
                DependencyGroupToRefresh = null,
                SecurityUpdatesOnly = true,
                UpdatingAPullRequest = false,
            },
            CreateSecurityUpdatePullRequestHandler.Instance,
        ];

        //
        // update_security_pr
        //
        yield return
        [
            new Job()
            {
                Source = CreateJobSource("/src"),
                Dependencies = ["Some.Dependency"],
                DependencyGroups = [],
                DependencyGroupToRefresh = null,
                SecurityUpdatesOnly = true,
                UpdatingAPullRequest = true,
            },
            RefreshSecurityUpdatePullRequestHandler.Instance,
        ];

        //
        // update_version_pr
        //
        yield return
        [
            new Job()
            {
                Source = CreateJobSource("/src"),
                Dependencies = ["Some.Dependency"], // must not be empty
                DependencyGroups = [],
                DependencyGroupToRefresh = null,
                SecurityUpdatesOnly = false, // must be false
                UpdatingAPullRequest = true, // must be true
            },
            RefreshVersionUpdatePullRequestHandler.Instance,
        ];
    }
}
