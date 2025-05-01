using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Test.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Run;

public class HttpApiHandlerTests
{
    [Theory]
    [MemberData(nameof(ErrorsAreSentToTheCorrectEndpointTestData))]
    public async Task ErrorsAreSentToTheCorrectEndpoint(JobErrorBase error, params string[] expectedEndpoints)
    {
        // arrange
        var actualEndpoints = new List<string>();
        using var http = TestHttpServer.CreateTestStringServer((method, url) =>
        {
            var expectedPrefix = "/update_jobs/TEST-ID/";
            var actualPathAndQuery = new Uri(url).PathAndQuery;
            if (!actualPathAndQuery.StartsWith(expectedPrefix))
            {
                throw new Exception($"Didn't find expected prefix: [{expectedPrefix}]");
            }

            actualEndpoints.Add(actualPathAndQuery[expectedPrefix.Length..]);
            return (200, "ok");
        });
        var handler = new HttpApiHandler(http.BaseUrl, "TEST-ID");

        // act
        await handler.RecordUpdateJobError(error);

        // assert
        AssertEx.Equal(expectedEndpoints, actualEndpoints);
    }

    [Fact]
    public void ErrorsAreSentToTheCorrectEndpoint_AllTypesAreTested()
    {
        var remainingErrorTypes = typeof(JobErrorBase).Assembly
            .GetTypes()
            .Where(t => t.IsSubclassOf(typeof(JobErrorBase)))
            .Select(t => t.Name)
            .ToHashSet();
        foreach (var testData in ErrorsAreSentToTheCorrectEndpointTestData())
        {
            var seenErrorType = testData[0].GetType().Name;
            remainingErrorTypes.Remove(seenErrorType);
        }

        Assert.Empty(remainingErrorTypes);
    }

    public static IEnumerable<object[]> ErrorsAreSentToTheCorrectEndpointTestData()
    {
        yield return [new BadRequirement("unused"), "record_update_job_error"];
        yield return [new DependencyFileNotFound("unused"), "record_update_job_error"];
        yield return [new DependencyFileNotParseable("unused"), "record_update_job_error"];
        yield return [new DependencyNotFound("unused"), "record_update_job_error"];
        yield return [new JobRepoNotFound("unused"), "record_update_job_error"];
        yield return [new PrivateSourceAuthenticationFailure(["unused"]), "record_update_job_error"];
        yield return [new PrivateSourceBadResponse(["unused"]), "record_update_job_error"];
        yield return [new PullRequestExistsForLatestVersion("unused", "unused"), "record_update_job_error"];
        yield return [new SecurityUpdateNotNeeded("unused"), "record_update_job_error"];
        yield return [new UnknownError(new Exception("unused"), "unused"), "record_update_job_error", "record_update_job_unknown_error", "increment_metric"];
        yield return [new UpdateNotPossible(["unused"]), "record_update_job_error"];
    }
}
