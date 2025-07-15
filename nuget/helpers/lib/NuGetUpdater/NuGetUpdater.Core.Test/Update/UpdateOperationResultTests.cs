using System.Text.Json;

using NuGet.Versioning;

using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Updater;

using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public partial class UpdateOperationResultTests
{
    [Fact]
    public void ResultFileHasCorrectShapeForAuthenticationFailure()
    {
        var result = new UpdateOperationResult()
        {
            Error = new PrivateSourceAuthenticationFailure(["<some package feed>"]),
            UpdateOperations = [],
        };
        var resultContent = UpdaterWorker.Serialize(result);

        // raw result file should look like this:
        // {
        //   ...
        //   "Error": {
        //     "error-type": "private_source_authentication_failure",
        //     "error-details": {
        //       "source": "<some package feed>"
        //     }
        //   }
        //   ...
        // }
        var jsonDocument = JsonDocument.Parse(resultContent);
        var error = jsonDocument.RootElement.GetProperty("Error");
        var errorType = error.GetProperty("error-type");
        var errorDetails = error.GetProperty("error-details");
        var source = errorDetails.GetProperty("source");

        Assert.Equal("private_source_authentication_failure", errorType.GetString());
        Assert.Equal("(<some package feed>)", source.GetString());
    }

    [Fact]
    public void ResultFileListsUpdateOperations()
    {
        var result = new UpdateOperationResult()
        {
            Error = null,
            UpdateOperations = [
                new DirectUpdate()
                    {
                        DependencyName = "Package.A",
                        OldVersion = NuGetVersion.Parse("0.1.0"),
                        NewVersion = NuGetVersion.Parse("1.0.0"),
                        UpdatedFiles = ["a.txt"]
                    },
                    new PinnedUpdate()
                    {
                        DependencyName = "Package.B",
                        OldVersion = NuGetVersion.Parse("0.2.0"),
                        NewVersion = NuGetVersion.Parse("2.0.0"),
                        UpdatedFiles = ["b.txt"]
                    },
                    new ParentUpdate()
                    {
                        DependencyName = "Package.C",
                        OldVersion = NuGetVersion.Parse("0.3.0"),
                        NewVersion = NuGetVersion.Parse("3.0.0"),
                        UpdatedFiles = ["c.txt"],
                        ParentDependencyName = "Package.D",
                        ParentNewVersion = NuGetVersion.Parse("4.0.0"),
                    }
            ]
        };
        var actualJson = UpdaterWorker.Serialize(result).Replace("\r", "");
        var expectedJson = """
                {
                  "UpdateOperations": [
                    {
                      "Type": "DirectUpdate",
                      "DependencyName": "Package.A",
                      "OldVersion": "0.1.0",
                      "NewVersion": "1.0.0",
                      "UpdatedFiles": [
                        "a.txt"
                      ]
                    },
                    {
                      "Type": "PinnedUpdate",
                      "DependencyName": "Package.B",
                      "OldVersion": "0.2.0",
                      "NewVersion": "2.0.0",
                      "UpdatedFiles": [
                        "b.txt"
                      ]
                    },
                    {
                      "Type": "ParentUpdate",
                      "ParentDependencyName": "Package.D",
                      "ParentNewVersion": "4.0.0",
                      "DependencyName": "Package.C",
                      "OldVersion": "0.3.0",
                      "NewVersion": "3.0.0",
                      "UpdatedFiles": [
                        "c.txt"
                      ]
                    }
                  ],
                  "Error": null
                }
                """.Replace("\r", "");
        Assert.Equal(expectedJson, actualJson);
    }
}
