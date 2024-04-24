using System;
using System.Collections.Generic;
using System.Threading.Tasks;

using Xunit;

namespace NuGetUpdater.Cli.Test;

public partial class EntryPointTests
{
    public class FrameworkCheck
    {
        [Theory]
        [InlineData("net7.0", "net5.0")]
        [InlineData("net7.0 net472", "net5.0 net461")]
        [InlineData("net7.0 net472", "netstandard2.0")]
        public Task Compatible(string projectTfms, string packageTfms)
            => Run(projectTfms, packageTfms, expectedExitCode: 0);

        [Theory]
        [InlineData("net5.0", "net7.0")]
        [InlineData("net5.0 net461", "net7.0 net472")]
        [InlineData("net5.0 net45", "netstandard2.0_brettfo")]
        public Task Incompatible(string projectTfms, string packageTfms)
            => Run(projectTfms, packageTfms, expectedExitCode: 1);

        private static async Task Run(string projectTfms, string packageTfms, int expectedExitCode)
        {
            var args = new List<string>();
            args.Add("framework-check");
            args.Add("--project-tfms");
            args.AddRange(projectTfms.Split(' ', StringSplitOptions.TrimEntries));
            args.Add("--package-tfms");
            args.AddRange(packageTfms.Split(' ', StringSplitOptions.TrimEntries));
            args.Add("--verbose");

            var actual = await Program.Main(args.ToArray());

            Assert.Equal(expectedExitCode, actual);
        }
    }
}
