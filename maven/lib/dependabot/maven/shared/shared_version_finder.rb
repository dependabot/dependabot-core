# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/package/package_latest_version_finder"

module Dependabot
  module Maven
    module Shared
      class SharedVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        # Regex to match common Maven release qualifiers that indicate stable releases.
        # See https://github.com/apache/maven/blob/848fbb4bf2d427b72bdb2471c22fced7ebd9a7a1/maven-artifact/src/main/java/org/apache/maven/artifact/versioning/ComparableVersion.java#L315-L320
        MAVEN_RELEASE_QUALIFIERS = /
          ^.+[-._](
            RELEASE|# Official release
            FINAL|# Final build
            GA# General Availability
          )$
        /ix

        # Common Maven pre-release qualifiers.
        # They often indicate versions that are not yet stable but that are released to the public for testing.
        # Examples: 1.0.0-RC1, 2.0.0-ALPHA2, 3.1.0-BETA, 4.0.0-DEV5, etc.
        # See https://maven.apache.org/guides/mini/guide-naming-conventions.html#version-identifier
        MAVEN_PRE_RELEASE_QUALIFIERS = /
            [-._]?(
              # --- Qualifiers that usually REQUIRE a number ---
              # Examples: "RC1", "BETA2", "M3", "ALPHA-1", "EAP.2"
              # The number differentiates multiple pre-releases; a version like "1.0.0-RC"
              (?i)(?:RC|CR|M|MILESTONE|ALPHA|BETA|EA|EAP)(?:[-._]?\d+)?
              |
              # --- Qualifiers that do NOT usually have numbers ---
              DEV|
              PREVIEW|
              PRERELEASE|
              EXPERIMENTAL|
              UNSTABLE
            )$
          /ix

        MAVEN_SNAPSHOT_QUALIFIER = /-SNAPSHOT$/i

        # Minimum and maximum lengths for Git SHAs
        MIN_GIT_SHA_LENGTH = 7
        MAX_GIT_SHA_LENGTH = 40

        # Regex for a valid Git SHA
        # - Only hexadecimal characters (0-9, a-f)
        # - Case-insensitive
        # - At least one letter a-f to avoid purely numeric strings
        GIT_COMMIT = T.let(
          /\A(?=[0-9a-f]{#{MIN_GIT_SHA_LENGTH},#{MAX_GIT_SHA_LENGTH}}\z)(?=.*[a-f])/i,
          Regexp
        )

        sig { params(comparison_version: Dependabot::Version).returns(T::Boolean) }
        def matches_dependency_version_type?(comparison_version)
          return true unless dependency.version

          current = dependency.version
          candidate = comparison_version.to_s

          return true if pre_release_compatible?(current, candidate)

          return true if upgrade_to_stable?(current, candidate)

          suffix_compatible?(current, candidate)
        end

        private

        # Determines whether two versions have compatible suffixes.
        #
        # Suffix compatibility is evaluated based on the type of suffix present:
        #
        # - Java runtime suffixes (JRE/JDK): Must have matching major versions and
        #   compatible runtime types (JRE can upgrade to JDK, but not vice versa)
        #
        # - Git commit SHAs: When any of the versions contain Git SHAs, they are considered irrelevant
        #   for compatibility purposes,
        #   as SHAs indicate specific build states rather than compatibility constraints.
        #
        # - Other suffixes: Must match exactly (e.g., platform identifiers, build tags)
        #
        # - No suffix: Both versions must have no suffix
        #
        # @example Java runtime compatibility
        #   suffix_compatible?("1.0.0.jre8", "1.0.0.jre8")   # => true  (same JRE version)
        #   suffix_compatible?("1.0.0.jre8", "1.0.0.jdk8")   # => true  (JRE → JDK upgrade)
        #   suffix_compatible?("1.0.0.jdk8", "1.0.0.jre8")   # => false (JDK → JRE downgrade)
        #   suffix_compatible?("1.0.0.jre8", "1.0.0.jre11")  # => false (version mismatch)
        #
        # @example Git SHA compatibility
        #   suffix_compatible?("1.0-a1b2c3d", "1.0-e5f6789") # => true  (both have SHAs)
        #   suffix_compatible?("1.0-a1b2c3d", "1.0.0") # => true ( considered irrelevant for compatibility)
        #
        # @example Exact suffix matching
        #   suffix_compatible?("1.0.0-linux", "1.0.0-linux") # => true  (exact match)
        #   suffix_compatible?("1.0.0-linux", "1.0.0-win")   # => false (different platform)
        #   suffix_compatible?("1.0.0", "1.0.0")             # => true  (both have no suffix)
        #   suffix_compatible?("1.0.0", "1.0.0-beta")        # => false (suffix mismatch)
        sig { params(current: T.nilable(String), candidate: String).returns(T::Boolean) }
        def suffix_compatible?(current, candidate)
          current_suffix = extract_version_suffix(current)
          candidate_suffix = extract_version_suffix(candidate)

          if jre_or_jdk?(current_suffix) && jre_or_jdk?(candidate_suffix)
            return compatible_java_runtime?(T.must(current_suffix), T.must(candidate_suffix))
          end

          return true if contains_git_sha?(current_suffix) || contains_git_sha?(candidate_suffix)

          # If both versions share the exact suffix or no suffix, they are compatible
          current_suffix == candidate_suffix
        end

        # Determines whether a given string is a valid Git commit SHA.
        #
        # Accepts both short SHAs (7-40 characters) and full SHAs (40 characters).
        # Handles versions with a leading 'v' prefix (e.g., "v018aa6b0d3").
        #
        # @example Valid Git SHAs
        #   git_sha?("a1b2c3d")           # => true  (7-char short SHA)
        #   git_sha?("a1b2c3d4e5f6")      # => true  (12-char SHA)
        #   git_sha?("a1b2c3d4e5f67890a1b2c3d4e5f67890a1b2c3d4") # => true (40-char full SHA)
        #   git_sha?("v018aa6b0d3")       # => true  (with 'v' prefix)
        #
        # @example Invalid inputs
        #   git_sha?("1.2.3")             # => false (version number)
        #   git_sha?("abc")               # => false (too short, < 7 chars)
        #   git_sha?("ghijklm")           # => false (invalid hex characters)
        #   git_sha?(nil)                 # => false (nil input)
        sig { params(version: T.nilable(String)).returns(T::Boolean) }
        def git_sha?(version)
          return false unless version

          normalized = version.start_with?("v") ? version[1..-1] : version
          !!T.must(normalized).match?(GIT_COMMIT)
        end

        # Determines whether a version string contains a Git commit SHA.
        #
        # This method checks if any part of a version string (when split by common
        # delimiters like '-', '.', or '_') is a valid Git SHA. It also handles
        # cases where delimiters within the SHA itself have been replaced with
        # underscores or other characters.

        # @example Standard delimiter-separated SHAs
        #   contains_git_sha?("1.0.0-a1b2c3d")     # => true  (SHA after hyphen)
        #   contains_git_sha?("2.3.4.a1b2c3d4e5")  # => true  (SHA after dot)
        #   contains_git_sha?("v1.2_a1b2c3d")      # => true  (SHA after underscore)
        #
        # @example Embedded SHAs with modified delimiters
        #   contains_git_sha?("va_b_018a_a_6b_0d3") # => true  (SHA with underscores replacing chars)
        #   contains_git_sha?("1.0.a.1.b.2.c.3.d") # => true  (SHA scattered across segments)
        #
        # @example Non-SHA versions
        #   contains_git_sha?("1.2.3")             # => false (regular version)
        #   contains_git_sha?("abc")               # => false (too short)
        #   contains_git_sha?(nil)                 # => false (nil input)
        sig { params(version: T.nilable(String)).returns(T::Boolean) }
        def contains_git_sha?(version)
          return false unless version

          # Check if any delimiter-separated part is a SHA
          version.split(/[-._]/).any? { |part| git_sha?(part) } ||
            # Check if removing delimiters reveals a SHA (e.g., "va_b_018a_a_6b_0d3")
            git_sha?(version.gsub(/[-._]/, ""))
        end

        # Determines whether two versions are compatible based on pre-release status.
        #
        # Two versions are considered compatible if both are pre-release versions.
        # This allows upgrades between different pre-release qualifiers of the same
        # base version (e.g., RC1 → CR2, ALPHA → BETA)
        #
        # @example Compatible pre-release transitions
        #   pre_release_compatible?("1.0.0-RC1", "1.0.0-RC2")    # => true  (same qualifier)
        #   pre_release_compatible?("1.0.0-RC1", "1.0.0-CR2")    # => true  (different qualifier, same stage)
        #   pre_release_compatible?("2.0.0-ALPHA", "2.0.0-BETA") # => true  (progression)
        #   pre_release_compatible?("1.5-M1", "1.5-MILESTONE2")  # => true  (equivalent qualifiers)
        sig { params(current: T.nilable(String), candidate: String).returns(T::Boolean) }
        def pre_release_compatible?(current, candidate)
          pre_release?(current) && pre_release?(candidate)
        end

        sig { params(version: T.nilable(String)).returns(T::Boolean) }
        def pre_release?(version)
          version&.match?(MAVEN_PRE_RELEASE_QUALIFIERS) || false
        end

        sig { params(version: T.nilable(String)).returns(T::Boolean) }
        def snapshot?(version)
          version&.match?(MAVEN_SNAPSHOT_QUALIFIER) || false
        end

        # This method allows upgrades from unstable versions (pre-releases or snapshots)
        # to stable releases, which is a common and expected upgrade path.
        # However, it prevents downgrades from stable releases back to pre-releases,
        # as this would violate semantic versioning expectations.
        #
        # @example Valid upgrades to stable
        #   upgrade_to_stable?("1.0.0-RC1", "1.0.0")          # => true  (pre-release → stable)
        #   upgrade_to_stable?("2.0.0-SNAPSHOT", "2.0.0")     # => true  (snapshot → stable)
        #   upgrade_to_stable?("1.5-BETA", "1.5")             # => true  (beta → stable)
        #   upgrade_to_stable?("3.0.0-ALPHA2", "3.0.0-FINAL") # => true  (pre-release → release qualifier)
        #
        # @example Invalid transitions (returns false)
        #   upgrade_to_stable?("1.0.0", "1.0.1-RC1")          # => false (stable → pre-release not allowed)
        #   upgrade_to_stable?("2.0.0", "2.1.0")              # => false (stable → stable, use other logic)
        #   upgrade_to_stable?("1.0.0-RC1", "1.0.0-BETA")     # => false (pre-release → pre-release)
        #   upgrade_to_stable?(nil, "1.0.0")                  # => false (no current version)
        sig { params(current: T.nilable(String), candidate: String).returns(T::Boolean) }
        def upgrade_to_stable?(current, candidate)
          (pre_release?(current) || snapshot?(current)) && !pre_release?(candidate)
        end

        # Determines whether two Java runtime suffixes are compatible.
        #
        # Compatibility rules:
        # - Both suffixes must be present and parseable.
        # - Java major versions must match (e.g., jdk8 != jdk11).
        # - JDK → JRE is NOT compatible (runtime capability downgrade).
        # - JRE → JDK is compatible (the JDK includes the JRE).
        # - JRE → JRE and JDK → JDK are compatible when versions match.
        # @example
        #   compatible_java_runtime?("jre8", "jre8")   # => true   (same version, JRE → JRE)
        #   compatible_java_runtime?("jdk8", "jdk8")   # => true   (same version, JDK → JDK)
        #   compatible_java_runtime?("jre8", "jdk8")   # => true   (JRE → JDK is compatible)
        #   compatible_java_runtime?("jdk8", "jre8")   # => false  (JDK → JRE is NOT compatible)
        #   compatible_java_runtime?("jre8", "jre11")  # => false  (version mismatch)
        #   compatible_java_runtime?("jdk8", "jdk11")  # => false  (version mismatch)
        sig do
          params(
            current_suffix: String,
            candidate_suffix: String
          ).returns(T::Boolean)
        end
        def compatible_java_runtime?(current_suffix, candidate_suffix)
          current_major_version = java_major_version(current_suffix)
          candidate_major_version = java_major_version(candidate_suffix)
          return false unless current_major_version == candidate_major_version

          is_downgrade = jdk?(current_suffix) && jre?(candidate_suffix)

          !is_downgrade
        end

        # Extracts the major Java version number from a JRE/JDK version suffix.
        #
        # @example
        #   java_major_version("jre8")  # => 8
        #   java_major_version("jdk17") # => 17
        sig { params(jre_jdk_suffix: String).returns(Integer) }
        def java_major_version(jre_jdk_suffix)
          jre_jdk_suffix[/\d+/].to_i
        end

        sig { params(version: T.nilable(String)).returns(T::Boolean) }
        def jre_or_jdk?(version)
          jre?(version) || jdk?(version)
        end

        # Matches if the current version is a JRE version suffix.
        #
        # @example
        #   jre?( "jre8") # => true
        #   jre?("jdk8") # => false
        sig { params(version: T.nilable(String)).returns(T::Boolean) }
        def jre?(version)
          return false unless version

          version.match?(/\A(jre)\d+\z/i)
        end

        # Matches if the current version is a JDK version suffix.
        #
        # @example
        #   jdk?("jre8")  # => false
        #   jdk?("jdk8") # => true
        sig { params(version: T.nilable(String)).returns(T::Boolean) }
        def jdk?(version)
          return false unless version

          version.match?(/\A(jdk)\d+\z/i)
        end

        # Extracts the qualifier/suffix from a Maven version string.
        #
        # Maven versions consist of numeric parts and optional string qualifiers.
        # This method identifies the suffix by finding the first segment (separated by '.')
        # that contains a non-digit character.
        sig { params(version_string: T.nilable(String)).returns(T.nilable(String)) }
        def extract_version_suffix(version_string)
          return nil unless version_string

          # Exclude common Maven release qualifiers that indicate stable releases
          return nil if version_string.match?(MAVEN_RELEASE_QUALIFIERS)

          version_string.split(".").each do |part|
            # Skip fully numeric segments
            next if part.match?(/\A\d+\z/)

            # strip leading digits and capture the suffix
            suffix = part.sub(/\A\d+/, "")
            # Normalize delimiters to ensure consistent comparison
            # e.g., "beta-1" and "beta_1" are treated the same
            suffix = suffix.tr("-", "_")

            # Special case for JDK/JRE suffixes
            # e.g., "13.2.1.jre8" or "13.2.1-jdk8"
            # In Java, these suffixes often indicate compatibility with specific Java runtimes
            # and are meaningful in version comparisons as we should not mix versions built for different runtimes.
            # For example, "1.0.0.jdk8" should not be considered the same as "1.0.0.jdk11"
            # because they target different Java versions.
            return suffix if jre_or_jdk?(suffix)

            # Ignore purely numeric suffixes (e.g., "-1", "_2")
            # e.g., "1.0.0-1" or "1.0.0_2" are not considered to have a meaningful suffix
            return nil if suffix.match?(/^_?\d+$/)

            return suffix if suffix.include?("-") || suffix.include?("_") || git_sha?(suffix)
          end

          nil
        end

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          raise NotImplementedError, "Subclasses must implement `package_details`"
        end
      end
    end
  end
end
