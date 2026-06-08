using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

using NuGetUpdater.Core.Discover;

using Xunit;
using Xunit.Sdk;

namespace NuGetUpdater.Core.Test.Utilities;

public class LoggerTests
{
    [Fact]
    public void OpenTelemetryToConsoleTest()
    {
        var outputBuilder = new StringBuilder();
        var writer = new StringWriter(outputBuilder);

        var originalOut = Console.Out;
        var originalError = Console.Error;
        Console.SetOut(writer);
        Console.SetError(writer);
        try
        {
            var logger = new OpenTelemetryLogger();
            logger.Info("Hello world");
            // The required console output is supposed to be YYYY/MM/DD HH:MM:SS INFO [Text]
            Assert.Matches(@"^\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2} INFO Hello world", outputBuilder.ToString());
        }
        finally
        {
            Console.SetOut(originalOut);
            Console.SetOut(originalError);
        }
    }

    [Fact]
    public void LogRaw_ShouldStreamLogsIndividually()
    {
        var consoleOutput = new StringWriter();
        Console.SetOut(consoleOutput);

        var logger = new OpenTelemetryLogger();

        var testMessage1 = "Log message 1";
        var testMessage2 = "Log message 2";

        logger.LogRaw(testMessage1);
        string output = consoleOutput.ToString();
        Assert.Contains(testMessage1, output);


        logger.LogRaw(testMessage2);
        output = consoleOutput.ToString();
        Assert.Contains(testMessage2, output);
    }

    [Fact]
    public void ReportDiscovery_LogsWarningForProjectsWithNU1701()
    {
        var logger = new StringLogger();
        var discoveryResult = new WorkspaceDiscoveryResult()
        {
            Path = "/src",
            Projects = [
                new()
                {
                    FilePath = "zebra.csproj",
                    Dependencies = [],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                    HasNoWarnNU1701 = true,
                },
                new()
                {
                    FilePath = "middle.csproj",
                    Dependencies = [],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                    HasNoWarnNU1701 = false,
                },
                new()
                {
                    FilePath = "alpha.csproj",
                    Dependencies = [],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                    HasNoWarnNU1701 = true,
                },
            ]
        };

        logger.ReportDiscovery(discoveryResult);

        var warnings = logger.Messages.Where(m => m.Contains("has NoWarn property containing NU1701; package compatibility checks may be inaccurate.")).ToList();
        Assert.Equal(2, warnings.Count);
        Assert.Contains("/src/alpha.csproj", warnings[0]);
        Assert.Contains("/src/zebra.csproj", warnings[1]);
        Assert.DoesNotContain(logger.Messages, m => m.Contains("Project [/src/middle.csproj] has NoWarn property containing NU1701; package compatibility checks may be inaccurate."));
    }
}
