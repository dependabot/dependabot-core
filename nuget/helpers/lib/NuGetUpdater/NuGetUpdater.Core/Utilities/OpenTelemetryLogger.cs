using System.Globalization;

using Microsoft.Extensions.Logging;

using OpenTelemetry;
using OpenTelemetry.Logs;

namespace NuGetUpdater.Core
{
    public class OpenTelemetryLogger : ILogger, IDisposable
    {
        private readonly ILoggerFactory _loggerFactory;
        private readonly Microsoft.Extensions.Logging.ILogger _logger;

        public OpenTelemetryLogger()
        {
            _loggerFactory = LoggerFactory.Create(builder =>
            {
                builder.AddOpenTelemetry(logging =>
                {
                    logging.AddProcessor(new SimpleLogRecordExportProcessor(new CustomConsoleExporter()));
                    logging.AddOtlpExporter();
                });
            });

            _logger = _loggerFactory.CreateLogger<OpenTelemetryLogger>();
        }

        public void LogRaw(string message)
        {
            _logger.LogInformation(message);
        }

        public void Dispose()
        {
            _loggerFactory?.Dispose();
        }
    }

    // We do this because the exporter that comes from AddConsoleExporter() prepends "LogRecord.Timestamp" in front of strings 
    internal class CustomConsoleExporter : BaseExporter<LogRecord>
    {
        public override ExportResult Export(in Batch<LogRecord> batch)
        {
            foreach (var logRecord in batch)
            {
                Console.WriteLine(logRecord.Body ?? string.Empty);
            }

            return ExportResult.Success;
        }
    }

}
