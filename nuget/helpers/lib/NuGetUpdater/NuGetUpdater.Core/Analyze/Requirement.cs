using System.Collections.Immutable;

using NuGet.Versioning;

namespace NuGetUpdater.Core.Analyze;

/// <summary>
/// A Requirement is a set of one or more version restrictions. It supports a
/// few (=, !=, >, <, >=, <=, ~>) different restriction operators.
/// </summary>
/// <remarks>
/// See Gem::Version for a description on how versions and requirements work
/// together in RubyGems.
/// </remarks>
public class Requirement
{
    private static readonly ImmutableDictionary<string, Func<NuGetVersion, NuGetVersion, bool>> Operators = new Dictionary<string, Func<NuGetVersion, NuGetVersion, bool>>()
    {
        ["="] = (v, r) => v == r,
        ["!="] = (v, r) => v != r,
        [">"] = (v, r) => v > r,
        ["<"] = (v, r) => v < r,
        [">="] = (v, r) => v >= r,
        ["<="] = (v, r) => v <= r,
        ["~>"] = (v, r) => v >= r && v.Version < Bump(r),
    }.ToImmutableDictionary();

    public static Requirement Parse(string requirement)
    {
        var parts = requirement.Split(' ', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0 || parts.Length > 2)
        {
            throw new ArgumentException("Invalid requirement string", nameof(requirement));
        }

        var op = parts.Length == 1 ? "=" : parts[0];
        var version = NuGetVersion.Parse(parts[^1]);

        return new Requirement(op, version);
    }

    public string Operator { get; }
    public NuGetVersion Version { get; }

    public Requirement(string op, NuGetVersion version)
    {
        if (!Operators.ContainsKey(op))
        {
            throw new ArgumentException("Invalid operator", nameof(op));
        }

        Operator = op;
        Version = version;
    }

    public override string ToString()
    {
        return $"{Operator} {Version}";
    }

    public bool IsSatisfiedBy(NuGetVersion version)
    {
        return Operators[Operator](version, Version);
    }

    private static readonly Dictionary<string, Version> BumpMap = [];
    /// <summary>
    /// Return a new version object where the next to the last revision
    /// number is one greater (e.g., 5.3.1 => 5.4).
    /// </summary>
    /// <remarks>
    /// This logic intended to be similar to RubyGems Gem::Version#bump
    /// </remarks>
    public static Version Bump(NuGetVersion version)
    {
        if (BumpMap.TryGetValue(version.OriginalVersion!, out var bumpedVersion))
        {
            return bumpedVersion;
        }

        var versionParts = version.OriginalVersion! // Get the original string this version was created from
            .Split('-')[0] // Get the version part without pre-release
            .Split('.') // Split into Major.Minor.Patch.Revision if present
            .Select(int.Parse)
            .ToArray();

        if (versionParts.Length > 1)
        {
            versionParts = versionParts[..^1]; // Remove the last part
        }

        versionParts[^1]++; // Increment the new last part

        bumpedVersion = NuGetVersion.Parse(string.Join('.', versionParts)).Version;
        BumpMap[version.OriginalVersion!] = bumpedVersion;

        return bumpedVersion;
    }
}
