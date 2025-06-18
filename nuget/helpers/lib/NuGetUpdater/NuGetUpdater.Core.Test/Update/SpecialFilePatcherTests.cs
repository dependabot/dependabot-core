using System.Text;

using NuGetUpdater.Core.Updater;
using NuGetUpdater.Core.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public class SpecialFilePatcherTests
{
    [Fact]
    public async Task ByteOrderMarkIsMaintained()
    {
        // arrange
        using var tempDir = new TemporaryDirectory();
        var projectFilePath = Path.Join(tempDir.DirectoryPath, "project.csproj");
        var rawContent = Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes("<Project>content with BOM</Project>")).ToArray();
        Assert.True(rawContent.HasBOM(), "Expected byte order mark after initial write");
        await File.WriteAllBytesAsync(projectFilePath, rawContent, TestContext.Current.CancellationToken);

        // act
        using (var special = new SpecialImportsConditionPatcher(projectFilePath))
        {
            var rawContentDuringPatching = await File.ReadAllBytesAsync(projectFilePath, TestContext.Current.CancellationToken);
            Assert.True(rawContentDuringPatching.HasBOM(), "Expected byte order mark during patching");
        }

        // assert
        var rawContentAfterPatching = await File.ReadAllBytesAsync(projectFilePath, TestContext.Current.CancellationToken);
        Assert.True(rawContentAfterPatching.HasBOM(), "Expected byte order mark after patching");
    }

    [Theory]
    [MemberData(nameof(SpecialImportsConditionPatcherTestData))]
    public async Task SpecialImportsConditionPatcher(string fileContent, string expectedPatchedContent)
    {
        // arrange
        var projectFileName = "project.csproj";
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync((projectFileName, fileContent));
        var projectPath = Path.Join(tempDir.DirectoryPath, projectFileName);

        // act
        using (var patcher = new SpecialImportsConditionPatcher(projectPath))
        {
            var actualPatchedContent = await File.ReadAllTextAsync(projectPath);

            // assert
            Assert.Equal(expectedPatchedContent.Replace("\r", ""), actualPatchedContent.Replace("\r", ""));
        }

        // assert again
        var restoredContent = await File.ReadAllTextAsync(projectPath);
        Assert.Equal(restoredContent.Replace("\r", ""), fileContent.Replace("\r", ""));
    }

    public static IEnumerable<object[]> SpecialImportsConditionPatcherTestData()
    {
        // magic file names

        // one-off test to verify namespaces don't interfere
        yield return
        [
            // fileContent
            """
            <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
              <Import Project="Unrelated.One.targets" />
              <Import Project="Some\Path\Microsoft.WebApplication.targets" />
              <Import Project="Unrelated.Two.targets" />
            </Project>
            """,
            // expectedPatchedContent
            """
            <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
              <Import Project="Unrelated.One.targets" />
              <Import Project="Some\Path\Microsoft.WebApplication.targets" Condition="false" />
              <Import Project="Unrelated.Two.targets" />
            </Project>
            """
        ];

        // one-off test to verify existing conditions are restored
        yield return
        [
            // fileContent
            """
            <Project>
              <Import Project="Unrelated.One.targets" />
              <Import Project="Some\Path\Microsoft.WebApplication.targets" Condition="existing condition" />
              <Import Project="Unrelated.Two.targets" />
            </Project>
            """,
            // expectedPatchedContent
            """
            <Project>
              <Import Project="Unrelated.One.targets" />
              <Import Project="Some\Path\Microsoft.WebApplication.targets" Condition="false" />
              <Import Project="Unrelated.Two.targets" />
            </Project>
            """
        ];

        // all file variations - by its nature, also verifies that multiple replacements can occur
        yield return
        [
            // fileContent
            """
            <Project>
              <Import Project="Unrelated.One.targets" />
              <Import Project="Some\Path\Microsoft.TextTemplating.targets" />
              <Import Project="Some\Path\Microsoft.WebApplication.targets" />
              <Import Project="Unrelated.Two.targets" />
            </Project>
            """,
            // expectedPatchedContent
            """
            <Project>
              <Import Project="Unrelated.One.targets" />
              <Import Project="Some\Path\Microsoft.TextTemplating.targets" Condition="false" />
              <Import Project="Some\Path\Microsoft.WebApplication.targets" Condition="false" />
              <Import Project="Unrelated.Two.targets" />
            </Project>
            """
        ];

        // magic property segments
        yield return
        [
            // fileContent
            """
            <Project>
              <Import Project="$(PkgSome_Package)\build\Some.Package.targets" />
            </Project>
            """,
            // expectedPatchedContent
            """
            <Project>
              <Import Project="$(PkgSome_Package)\build\Some.Package.targets" Condition="false" />
            </Project>
            """
        ];
    }
}
