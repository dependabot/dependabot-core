using NuGetUpdater.Core.Updater.FileWriters;

using Xunit;

namespace NuGetUpdater.Core.Test.Update.FileWriters;

public class ExternalFileWriterTests
{
    [Fact]
    public void ExternalFileEditRequestCanBeSerialized()
    {
        // arrange
        var fileEditRequest = new FileEditRequest()
        {
            PackagesToUpdate = [new FileEditPackageInfo() { Name = "Some.Dependency", OldVersion = "1.0.0", NewVersion = "2.0.0" }],
            Files = [new FileEditFile() { Path = "/path/to/file", Content = "some content" }],
        };

        // act
        var actualJson = ExternalFileWriter.SerializeRequest(fileEditRequest);

        // assert
        var expectedJson = """
            {"packagesToUpdate":[{"name":"Some.Dependency","oldVersion":"1.0.0","newVersion":"2.0.0"}],"files":[{"path":"/path/to/file","content":"some content"}]}
            """;
        Assert.Equal(expectedJson, actualJson);
    }

    [Fact]
    public void ExternalFileEditResponseCanBeDeserialized()
    {
        // arrange
        var json = """
            {"success":true,"files":[{"path":"/path/to/file","content":"new content"}]}
            """;

        // act
        var response = ExternalFileWriter.DeserializeResponse(json);

        // assert
        Assert.NotNull(response);
        Assert.True(response.Success);
        var updatedFile = Assert.Single(response.Files);
        Assert.Equal("/path/to/file", updatedFile.Path);
        Assert.Equal("new content", updatedFile.Content);
    }

    [Fact]
    public async Task ExternalFileEditorMakesAppropriateHttpCalls()
    {
        // arrange
        var repoFilePath = "/path/to/file";
        var httpRequestPath = "edit";
        using var http = TestHttpServer.CreateTestStringServerWithBody((url, body) =>
        {
            var uri = new Uri(url, UriKind.Absolute);
            if (uri.PathAndQuery != $"/{httpRequestPath}")
            {
                return (404, "not found");
            }

            if (body is null)
            {
                return (400, "null request");
            }

            var request = ExternalFileWriter.DeserializeRequest(body);
            if (request is null)
            {
                return (400, "request was null");
            }

            if (request.PackagesToUpdate.Length != 1 || request.Files.Length != 1)
            {
                return (400, "unexpected object count");
            }

            if (request.PackagesToUpdate[0].Name != "Some.Dependency" ||
                request.PackagesToUpdate[0].OldVersion != "1.0.0" ||
                request.PackagesToUpdate[0].NewVersion != "2.0.0")
            {
                return (400, "unexpected package info");
            }

            if (request.Files[0].Path != repoFilePath || request.Files[0].Content != "original contents")
            {
                return (400, "unexpected file info");
            }

            var response = new FileEditResponse()
            {
                Success = true,
                Files = [new FileEditFile() { Path = repoFilePath, Content = "new contents" }],
            };
            var responseJson = ExternalFileWriter.SerializeResponse(response);
            return (200, responseJson);
        });
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync((repoFilePath.TrimStart('/'), "original contents"));
        var externalFileWriter = new ExternalFileWriter($"{http.BaseUrl}{httpRequestPath}", new TestLogger());

        // act
        var result = await externalFileWriter.UpdatePackageVersionsAsync(
            new DirectoryInfo(tempDir.DirectoryPath),
            [repoFilePath],
            [new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference)],
            [new Dependency("Some.Dependency", "2.0.0", DependencyType.PackageReference)],
            false
        );

        // assert
        Assert.True(result);
        var updatedFileContents = await File.ReadAllTextAsync(Path.Join(tempDir.DirectoryPath, repoFilePath), TestContext.Current.CancellationToken);
        var expectedContents = "new contents";
        Assert.Equal(expectedContents, updatedFileContents);
    }
}
