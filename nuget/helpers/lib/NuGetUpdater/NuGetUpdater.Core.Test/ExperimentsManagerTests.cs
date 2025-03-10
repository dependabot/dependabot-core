using Xunit;

namespace NuGetUpdater.Core.Test;

public class ExperimentsManagerTests
{
    [Fact]
    public async Task FromJobFileAsync_WithJobFileContainingInvalidJson_ShouldNotThrowExceptions()
    {
        var jobId = Guid.NewGuid().ToString();
        var jobPath = Path.Join(Path.GetTempPath(), Path.GetRandomFileName());
        File.WriteAllText(jobPath, """
            {
              "job": {
                "package-manager": "nuget",
                "allowed-updates": [
                  {
                    "update-type": "all"
                  }
                ],
                "source": {
                  "provider": "github",
                  "repo": "some-org/some-repo",
                  "directory": "specific-sdk",
                  "hostname": null,
                  "api-endpoint": null
                },
                "commit-message-options": {
                  "include-scope": "true"
                }
              }
            }
            """
        );

        try
        {
            var (manager, error) = await ExperimentsManager.FromJobFileAsync(jobId, jobPath);
        }
        catch (Exception ex)
        {
            Assert.Fail("Expected no exception, but got: " + ex.Message);
        }
    }

    [Fact]
    public async Task FromJobFileAsync_WithJobFileContainingInvalidJson_ShouldReturnError()
    {
        var jobId = Guid.NewGuid().ToString();
        var jobPath = Path.Join(Path.GetTempPath(), Path.GetRandomFileName());
        File.WriteAllText(jobPath, """
            {
              "job": {
                "package-manager": "nuget",
                "allowed-updates": [
                  {
                    "update-type": "all"
                  }
                ],
                "source": {
                  "provider": "github",
                  "repo": "some-org/some-repo",
                  "directory": "specific-sdk",
                  "hostname": null,
                  "api-endpoint": null
                },
                "commit-message-options": {
                  "include-scope": "true"
                }
              }
            }
            """
        );

        var (manager, error) = await ExperimentsManager.FromJobFileAsync(jobId, jobPath);
        Assert.NotNull(error);
    }
}
