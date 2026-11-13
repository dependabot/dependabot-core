using System.Net;

using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Test.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Run;

public class HttpApiHandlerTests
{
    [Fact]
    public async Task FailedRequestWithContentReportsData()
    {
        // arrange
        // this mimics an error that can be returned by the server
        var errorContent = """{"errors":[{"status":400,"title":"Bad Request","detail":"some-detail"}]}""";
        using var http = TestHttpServer.CreateTestStringServer((method, url) =>
        {
            return (400, errorContent);
        });
        var handler = new HttpApiHandler(http.BaseUrl, "TEST-ID");

        // act
        var exception = await Assert.ThrowsAsync<HttpApiException>(() => handler.IncrementMetric(new()
        {
            // body is irrelevant for this test
            Metric = "TEST",
        }));

        // assert
        var expectedMessage = $"POST increment_metric failed with 400 (BadRequest): {errorContent}";
        Assert.Equal(expectedMessage, exception.Message);
        Assert.Equal("POST", exception.Method);
        Assert.Equal("increment_metric", exception.Endpoint);
        Assert.Equal(errorContent, exception.ResponseContent);
        Assert.Equal(HttpStatusCode.BadRequest, exception.StatusCode);
    }

    [Fact]
    public async Task FailedRequestWithNoContentOnlyReportsStatusCode()
    {
        // arrange
        using var http = TestHttpServer.CreateTestServer((method, url) =>
        {
            // no error content returned
            return (400, null);
        });
        var handler = new HttpApiHandler(http.BaseUrl, "TEST-ID");

        // act
        var exception = await Assert.ThrowsAsync<HttpApiException>(() => handler.IncrementMetric(new()
        {
            // body is irrelevant for this test
            Metric = "TEST",
        }));

        // assert
        var expectedMessage = $"POST increment_metric failed with 400 (BadRequest)";
        Assert.Equal(expectedMessage, exception.Message);
        Assert.Null(exception.ResponseContent);
    }

    [Fact]
    public async Task ForbiddenResponseFromCreatePullRequestIsReportedAsAnApiFailure()
    {
        // arrange
        var requestCount = 0;
        using var http = TestHttpServer.CreateTestStringServer((method, url) =>
        {
            requestCount++;
            return (403, "forbidden");
        });
        var handler = new HttpApiHandler(http.BaseUrl, "TEST-ID");

        // act
        var exception = await Assert.ThrowsAsync<HttpApiException>(() =>
            handler.CreatePullRequest(new()
            {
                Dependencies = [],
                UpdatedDependencyFiles = [],
                BaseCommitSha = "base-commit-sha",
                CommitMessage = "commit message",
                PrTitle = "PR title",
                PrBody = "PR body",
                DependencyGroup = null,
            }));

        // assert
        Assert.Equal("POST create_pull_request failed with 403 (Forbidden): forbidden", exception.Message);
        Assert.Equal("POST", exception.Method);
        Assert.Equal("create_pull_request", exception.Endpoint);
        Assert.Equal("forbidden", exception.ResponseContent);
        Assert.Equal(HttpStatusCode.Forbidden, exception.StatusCode);
        Assert.Equal(1, requestCount);
    }

    [Fact]
    public async Task ApiCallsAreAutomaticallyRetriedWhenTheServerThrowsAnError()
    {
        // arrange
        var requestCount = 0;
        using var http = TestHttpServer.CreateTestServer((method, url) =>
        {
            requestCount++;
            if (requestCount <= 2)
            {
                return (500, Array.Empty<byte>());
            }

            return (200, Array.Empty<byte>());
        });
        var handler = new HttpApiHandler(http.BaseUrl, "TEST-ID", static _ => Task.CompletedTask);

        // act
        await handler.IncrementMetric(new()
        {
            Metric = "test",
        });

        // assert
        Assert.Equal(3, requestCount);
    }

    [Fact]
    public async Task ApiCallsAreNotRetriedOnABadRequest()
    {
        // arrange
        var requestCount = 0;
        using var http = TestHttpServer.CreateTestServer((method, url) =>
        {
            requestCount++;
            return (400, Array.Empty<byte>());
        });
        var handler = new HttpApiHandler(http.BaseUrl, "TEST-ID");

        // act
        await Assert.ThrowsAsync<HttpApiException>(() => handler.IncrementMetric(new() { Metric = "test" }));

        // assert
        Assert.Equal(1, requestCount);
    }

    [Fact]
    public async Task ApiCallsStopRetryingAfterTheMaximumNumberOfAttempts()
    {
        // arrange
        var requestCount = 0;
        using var http = TestHttpServer.CreateTestStringServer((method, url) =>
        {
            requestCount++;
            return (500, $"attempt-{requestCount}");
        });
        var handler = new HttpApiHandler(http.BaseUrl, "TEST-ID", static _ => Task.CompletedTask);

        // act
        var exception = await Assert.ThrowsAsync<HttpApiException>(() => handler.IncrementMetric(new() { Metric = "test" }));

        // assert
        Assert.Equal("POST increment_metric failed with 500 (InternalServerError): attempt-4", exception.Message);
        Assert.Equal(4, requestCount);
    }

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
        await handler.RecordUpdateJobError(error, new TestLogger());

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
        yield return [new OutOfDisk(), "record_update_job_error"];
        yield return [new PrivateSourceAuthenticationFailure(["unused"]), "record_update_job_error"];
        yield return [new PrivateSourceBadResponse(["unused"], "unused"), "record_update_job_error"];
        yield return [new PrivateSourceTimedOut("unused"), "record_update_job_error"];
        yield return [new PullRequestExistsForLatestVersion("unused", "unused"), "record_update_job_error"];
        yield return [new PullRequestExistsForSecurityUpdate([]), "record_update_job_error"];
        yield return [new SecurityUpdateDependencyNotFound(), "record_update_job_error"];
        yield return [new SecurityUpdateIgnored("unused"), "record_update_job_error"];
        yield return [new SecurityUpdateNotFound("unused", "unused"), "record_update_job_error"];
        yield return [new SecurityUpdateNotNeeded("unused"), "record_update_job_error"];
        yield return [new SecurityUpdateNotPossible("unused", "unused", "unused", []), "record_update_job_error"];
        yield return [new UnknownError(new Exception("unused"), "unused"), "record_update_job_error", "record_update_job_unknown_error", "increment_metric"];
        yield return [new UpdateNotPossible(["unused"]), "record_update_job_error"];
    }
}
