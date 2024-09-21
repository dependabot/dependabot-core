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
public abstract class Requirement
{
    public abstract bool IsSatisfiedBy(NuGetVersion version);

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

    public static Requirement Parse(string requirement)
    {
        var specificParts = requirement.Split(',');
        if (specificParts.Length == 1)
        {
            return IndividualRequirement.ParseIndividual(requirement);
        }

        var specificRequirements = specificParts.Select(IndividualRequirement.ParseIndividual).ToArray();
        return new MultiPartRequirement(specificRequirements);
    }
}


public class IndividualRequirement : Requirement
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

    public string Operator { get; }
    public NuGetVersion Version { get; }

    public IndividualRequirement(string op, NuGetVersion version)
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

    public override bool IsSatisfiedBy(NuGetVersion version)
    {
        return Operators[Operator](version, Version);
    }

    public static IndividualRequirement ParseIndividual(string requirement)
    {
        var splitIndex = requirement.LastIndexOfAny(['=', '>', '<']);

        // Throw if the requirement is all operator and no version.
        if (splitIndex == requirement.Length - 1)
        {
            throw new ArgumentException($"`{requirement}` is a invalid requirement string", nameof(requirement));
        }

        string[] parts = splitIndex == -1
            ? [requirement.Trim()]
            : [requirement[..(splitIndex + 1)].Trim(), requirement[(splitIndex + 1)..].Trim()];

        var op = parts.Length == 1 ? "=" : parts[0];
        var versionString = parts[^1];

        // allow for single character wildcards; may be asterisk (NuGet-style: 1.*) or a single letter (alternate style: 1.x)
        var versionParts = versionString.Split('.');
        var recreatedVersionParts = versionParts.Select(vp => vp.Length == 1 && (vp == "*" || char.IsAsciiLetter(vp[0])) ? "0" : vp).ToArray();

        var rebuiltVersionString = string.Join(".", recreatedVersionParts);
        var version = NuGetVersion.Parse(rebuiltVersionString);

        return new IndividualRequirement(op, version);
    }
}

public class MultiPartRequirement : Requirement
{
    public ImmutableArray<IndividualRequirement> Parts { get; }

    public MultiPartRequirement(IndividualRequirement[] parts)
    {
        if (parts.Length <= 1)
        {
            throw new ArgumentException("At least two parts are required", nameof(parts));
        }

        Parts = parts.ToImmutableArray();
    }

    public override string ToString()
    {
        return string.Join(", ", Parts);
    }

    public override bool IsSatisfiedBy(NuGetVersion version)
    {
        return Parts.All(part => part.IsSatisfiedBy(version));
    }
}
