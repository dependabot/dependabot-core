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

        sig { params(comparison_version: Dependabot::Version).returns(T::Boolean) }
        def matches_dependency_version_type?(comparison_version)
          return true unless dependency.version

          current_version_string = dependency.version
          candidate_version_string = comparison_version.to_s

          current_is_pre_release = current_version_string&.match?(MAVEN_PRE_RELEASE_QUALIFIERS)
          candidate_is_pre_release = candidate_version_string.match?(MAVEN_PRE_RELEASE_QUALIFIERS)

          # Pre-releases are only compatible with other pre-releases
          # When this happens, the suffix does not need to match exactly
          # This allows transitions between 1.0.0-RC1 and 1.0.0-CR2, for example
          return true if current_is_pre_release && candidate_is_pre_release

          current_is_snapshot = current_version_string&.match?(MAVEN_SNAPSHOT_QUALIFIER)
          # If the current version is a pre-release or a snapshot, allow upgrading to a stable release
          # This can help move from pre-release to the stable version that supersedes it,
          # but this should not happen vice versa as a stable release should not be downgraded to a pre-release
          return true if (current_is_pre_release || current_is_snapshot) && !candidate_is_pre_release

          current_suffix = extract_version_suffix(current_version_string)
          candidate_suffix = extract_version_suffix(candidate_version_string)

          if jre_or_jdk?(current_suffix) && jre_or_jdk?(candidate_suffix)
            return compatible_java_runtime?(T.must(current_suffix), T.must(candidate_suffix))
          end

          # If both versions share the exact suffix or no suffix, they are compatible
          current_suffix == candidate_suffix
        end

        private

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

            # Must contain a hyphen to be considered a valid suffix
            return suffix if suffix.include?("-") || suffix.include?("_")
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
