using NuGetUpdater.Core.Run;

using Xunit;

namespace NuGetUpdater.Core.Test.Run;

public class SerializationTests
{
    [Fact]
    public void DeserializeJob()
    {
        var jobWrapper = RunWorker.Deserialize("""
            {
              "job": {
                "package-manager": "nuget",
                "allowed-updates": [
                  {
                    "update-type": "all"
                  }
                ],
                "debug": false,
                "dependency-groups": [],
                "dependencies": null,
                "dependency-group-to-refresh": null,
                "existing-pull-requests": [],
                "existing-group-pull-requests": [],
                "experiments": null,
                "ignore-conditions": [],
                "lockfile-only": false,
                "requirements-update-strategy": null,
                "security-advisories": [],
                "security-updates-only": false,
                "source": {
                  "provider": "github",
                  "repo": "some-org/some-repo",
                  "directory": "specific-sdk",
                  "hostname": null,
                  "api-endpoint": null
                },
                "update-subdependencies": false,
                "updating-a-pull-request": false,
                "vendor-dependencies": false,
                "reject-external-code": false,
                "repo-private": false,
                "commit-message-options": null,
                "credentials-metadata": [
                  {
                    "host": "github.com",
                    "type": "git_source"
                  }
                ],
                "max-updater-run-time": 0
              }
            }
            """);
        Assert.Equal("github", jobWrapper.Job.Source.Provider);
        Assert.Equal("some-org/some-repo", jobWrapper.Job.Source.Repo);
        Assert.Equal("specific-sdk", jobWrapper.Job.Source.Directory);
    }
}
