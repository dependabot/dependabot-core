extern alias CoreV2;

using System.Diagnostics.CodeAnalysis;
using System.Reflection;
using System.Text.RegularExpressions;

using Runtime_AssemblyBinding = CoreV2::NuGet.Runtime.AssemblyBinding;
using Runtime_IAssembly = CoreV2::NuGet.Runtime.IAssembly;

namespace NuGetUpdater.Core;

public static partial class BindingRedirectResolver
{
    public static IEnumerable<Runtime_AssemblyBinding> GetBindingRedirects(string projectPath, IEnumerable<string> includes)
    {
        var directoryPath = Path.GetDirectoryName(projectPath);
        if (directoryPath is null)
        {
            yield break;
        }

        foreach (var include in includes)
        {
            if (TryParseIncludesString(include, out var assemblyInfo))
            {
                yield return new Runtime_AssemblyBinding(assemblyInfo);
            }
        }

        yield break;

        static bool TryParseIncludesString(string include, [NotNullWhen(true)] out AssemblyWrapper? assemblyInfo)
        {
            assemblyInfo = null;
            var name = include.Split(',').FirstOrDefault();
            if (name is null)
            {
                return false;
            }

            var dict = IncludesRegex
                .Matches(include)
                .ToDictionary(static x => x.Groups["key"].Value, static x => x.Groups["value"].Value);

            if (!dict.TryGetValue("Version", out var versionString) ||
                !Version.TryParse(versionString, out var version))
            {
                return false;
            }

            var publicKeyToken = dict.GetValueOrDefault("PublicKeyToken", "null");
            var culture = dict.GetValueOrDefault("Culture", "neutral");

            assemblyInfo = new AssemblyWrapper(name, version, publicKeyToken, culture);
            return true;
        }
    }

    private static readonly Regex IncludesRegex = IncludesPattern();

    /// <summary>
    /// Wraps system<see cref="Assembly"/> type in the nuget interface <see cref="NuGet.Runtime.IAssembly"/> to interop with nuget apis
    /// </summary>
    private class AssemblyWrapper : Runtime_IAssembly
    {
        public AssemblyWrapper(string name, Version version, string publicKeyToken, string culture)
        {
            Name = name;
            Version = version;
            PublicKeyToken = publicKeyToken;
            Culture = culture;
        }

        public string Name { get; }
        public Version Version { get; }
        public string PublicKeyToken { get; }
        public string Culture { get; }
        public IEnumerable<Runtime_IAssembly> ReferencedAssemblies { get; } = Enumerable.Empty<AssemblyWrapper>();
    }

    [GeneratedRegex("(?<key>\\w+)=(?<value>[^,]+)")]
    private static partial Regex IncludesPattern();
}
