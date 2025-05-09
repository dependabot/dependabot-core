using System.Net;
using System.Text.Json;

using NuGet.Protocol.Core.Types;

using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;

using Xunit;

namespace NuGetUpdater.Core.Test.Run;

public class JobErrorBaseTests : TestBase
{
    [Theory]
    [MemberData(nameof(GenerateErrorFromExceptionTestData))]
    public async Task GenerateErrorFromException(Exception exception, JobErrorBase expectedError)
    {
        // arrange
        // some error types require a NuGet.Config file to be present
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync(
            ("NuGet.Config", """
                <configuration>
                  <packageSources>
                    <clear />
                    <add key="some_package_feed" value="http://nuget.example.com/v3/index.json" allowInsecureConnections="true" />
                  </packageSources>
                </configuration>
                """)
        );

        // act
        var actualError = JobErrorBase.ErrorFromException(exception, "TEST-JOB-ID", tempDir.DirectoryPath);

        // assert
        var actualErrorJson = JsonSerializer.Serialize(actualError, RunWorker.SerializerOptions);
        var expectedErrorJson = JsonSerializer.Serialize(expectedError, RunWorker.SerializerOptions);
        Assert.Equal(expectedErrorJson, actualErrorJson);
    }

    public static IEnumerable<object[]> GenerateErrorFromExceptionTestData()
    {
        // internal error from package feed
        yield return
        [
            new HttpRequestException("nope", null, HttpStatusCode.InternalServerError),
            new PrivateSourceBadResponse(["http://nuget.example.com/v3/index.json"]),
        ];

        // inner exception turns into private_source_bad_response
        yield return
        [
            new FatalProtocolException("nope", new HttpRequestException("nope", null, HttpStatusCode.InternalServerError)),
            new PrivateSourceBadResponse(["http://nuget.example.com/v3/index.json"]),
        ];

        // top-level exception turns into private_source_authentication_failure
        yield return
        [
            new HttpRequestException("nope", null, HttpStatusCode.Unauthorized),
            new PrivateSourceAuthenticationFailure(["http://nuget.example.com/v3/index.json"]),
        ];

        // inner exception turns into private_source_authentication_failure
        yield return
        [
            // the NuGet libraries commonly do this
            new FatalProtocolException("nope", new HttpRequestException("nope", null, HttpStatusCode.Unauthorized)),
            new PrivateSourceAuthenticationFailure(["http://nuget.example.com/v3/index.json"]),
        ];

        // unknown errors all the way down; report the initial top-level error
        yield return
        [
            new Exception("outer", new Exception("inner")),
            new UnknownError(new Exception("outer", new Exception("inner")), "TEST-JOB-ID"),
        ];
    }
}
