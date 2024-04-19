using System.Text;

using NuGetUpdater.Core.Test.Analyze;

using Xunit;

namespace NuGetUpdater.Cli.Test;

using TestFile = (string Path, string Content);

public partial class EntryPointTests
{
    public class Analyze : AnalyzeWorkerTestBase
    {
        private static async Task Run(Func<string, string[]> getArgs, string dependencyName, TestFile[] initialFiles, ExpectedAnalysisResult expectedResult)
        {
            var actualResult = await RunAnalyzerAsync(dependencyName, initialFiles, async path =>
            {
                var sb = new StringBuilder();
                var writer = new StringWriter(sb);

                var originalOut = Console.Out;
                var originalErr = Console.Error;
                Console.SetOut(writer);
                Console.SetError(writer);

                try
                {
                    var args = getArgs(path);
                    var result = await Program.Main(args);
                    if (result != 0)
                    {
                        throw new Exception($"Program exited with code {result}.\nOutput:\n\n{sb}");
                    }
                }
                finally
                {
                    Console.SetOut(originalOut);
                    Console.SetError(originalErr);
                }
            });

            ValidateAnalysisResult(expectedResult, actualResult);
        }
    }
}
