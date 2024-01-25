using System.Text.Json.Serialization;

using NuGetUpdater.Core;

namespace NuGetUpdater.Cli;

[JsonSourceGenerationOptions(
    PropertyNameCaseInsensitive = true,
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    GenerationMode = JsonSourceGenerationMode.Metadata
)]
[JsonSerializable(typeof(DependencyRequest))]
public partial class NugetUpdaterJsonSerializerContext : JsonSerializerContext;
