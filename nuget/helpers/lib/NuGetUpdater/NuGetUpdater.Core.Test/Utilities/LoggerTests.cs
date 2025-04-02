using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

using Xunit;

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
            Assert.Matches(@"^\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2} INFO Hello world", outputBuilder.ToString());
        }
        finally
        {
            Console.SetOut(originalOut);
            Console.SetOut(originalError);
        }
    }
}
