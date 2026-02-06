# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/maven/shared/shared_version_finder"
require "dependabot/maven/version"

RSpec.describe Dependabot::Maven::Shared::SharedVersionFinder do
  let(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      security_advisories: security_advisories,
      cooldown_options: cooldown_options
    )
  end
  let(:dependency_files) { [pom] }
  let(:pom) do
    Dependabot::DependencyFile.new(
      name: "pom.xml",
      content: fixture("poms", pom_fixture_name)
    )
  end
  let(:pom_fixture_name) { "basic_pom.xml" }
  let(:version_class) { Dependabot::Maven::Version }
  let(:credentials) { [] }
  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }
  let(:security_advisories) { [] }
  let(:cooldown_options) { nil }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "maven"
    )
  end
  let(:dependency_name) { "com.google.guava:guava" }
  let(:dependency_version) { "23.3-jre" }
  let(:dependency_requirements) do
    [{
      file: "pom.xml",
      requirement: dependency_version,
      groups: [],
      source: nil,
      metadata: { packaging_type: "jar" }
    }]
  end

  describe "#releases" do
    context "when comparing version types with suffixes" do
      subject { finder.send(:matches_dependency_version_type?, version_class.new(comparison_version)) }

      context "when the dependency has no suffix" do
        let(:dependency_version) { "1.0.0" }
        let(:comparison_version) { "1.1.0" }

        it { is_expected.to be true }
      end

      context "when the suffixes are the same" do
        let(:dependency_version) { "7.9.0-ccs" }
        let(:comparison_version) { "7.9.1-ccs" }

        it { is_expected.to be true }
      end

      context "when the suffixes are different" do
        let(:dependency_version) { "7.9.0-ccs" }
        let(:comparison_version) { "7.9.0-ce" }

        it { is_expected.to be false }
      end

      context "when only the version to compare has a suffix" do
        let(:dependency_version) { "1.0.0" }
        let(:comparison_version) { "1.1.0-css" }

        it { is_expected.to be false }
      end

      context "when the existing version has a suffix but the candidate doesn't" do
        let(:dependency_version) { "1.0.0-css" }
        let(:comparison_version) { "1.1.0" }

        it { is_expected.to be false }
      end

      context "when release candidates (rc) are presented" do
        let(:dependency_version) { "1.0.1" }
        let(:comparison_version) { "1.0.2-rc" }

        it { is_expected.to be false }
      end

      context "when release candidates (cr) are presented" do
        let(:dependency_version) { "1.0.1" }
        let(:comparison_version) { "1.0.2-cr" }

        it { is_expected.to be false }
      end

      context "when the dependency version has a numeric-only suffix" do
        let(:dependency_version) { "1.0.1-1" }
        let(:comparison_version) { "1.0.2" }

        it { is_expected.to be true }
      end

      context "when the comparison version has a numeric-only suffix" do
        let(:dependency_version) { "1.0.1" }
        let(:comparison_version) { "1.0.2-1" }

        it { is_expected.to be true }
      end

      context "when equivalent release candidates are presented" do
        context "when comparing CR and RC variants" do
          context "when upgrading from -cr to -rc" do
            let(:dependency_version) { "1.0.0-cr1" }
            let(:comparison_version) { "1.0.0-rc1" }

            it { is_expected.to be true }
          end

          context "when upgrading from -rc to -cr" do
            let(:dependency_version) { "1.0.0-rc1" }
            let(:comparison_version) { "1.0.0-cr1" }

            it { is_expected.to be true }
          end
        end

        context "when using mixed-case qualifiers" do
          context "when upgrading from -rc to -CR" do
            let(:dependency_version) { "1.0.0-rc1" }
            let(:comparison_version) { "1.0.0-cr1" }

            it { is_expected.to be true }
          end

          context "when upgrading from -CR to -rc" do
            let(:dependency_version) { "1.0.0-cr1" }
            let(:comparison_version) { "1.0.0-cr1" }

            it { is_expected.to be true }
          end
        end

        context "when the release candidates have numeric suffixes" do
          let(:dependency_version) { "1.0.0-cr11" }
          let(:comparison_version) { "1.0.0-rc11" }

          it { is_expected.to be true }
        end

        context "when using milestone releases" do
          context "when using short milestone notation" do
            let(:dependency_version) { "1.0.0-M1" }
            let(:comparison_version) { "1.0.0-M2" }

            it { is_expected.to be true }
          end

          context "when using fully qualified milestone notation" do
            let(:dependency_version) { "1.0.0-milestone-1" }
            let(:comparison_version) { "1.0.0-milestone-2" }

            it { is_expected.to be true }
          end
        end
      end

      context "when upgrading from a pre-release to a released version" do
        let(:comparison_version) { "1.0.0" }

        context "when upgrading from release candidate–like versions" do
          context "when upgrading from -cr to final version" do
            let(:dependency_version) { "1.0.0-cr1" }

            it { is_expected.to be true }
          end

          context "when upgrading from -rc to final version" do
            let(:dependency_version) { "1.0.0-rc1" }

            it { is_expected.to be true }
          end
        end

        context "when upgrading from early-stage versions" do
          context "when upgrading from -ALPHA to final version" do
            let(:dependency_version) { "1.0.0-ALPHA" }

            it { is_expected.to be true }
          end

          context "when upgrading from -BETA to final version" do
            let(:dependency_version) { "1.0.0-BETA" }

            it { is_expected.to be true }
          end

          context "when upgrading from -M1 to final version" do
            let(:dependency_version) { "1.0.0-M1" }

            it { is_expected.to be true }
          end
        end

        context "when upgrading from development and experimental versions" do
          context "when upgrading from -DEV to final version" do
            let(:dependency_version) { "1.0.0-DEV" }

            it { is_expected.to be true }
          end

          context "when upgrading from -EA to final version" do
            let(:dependency_version) { "1.0.0-EA-1" }

            it { is_expected.to be true }
          end

          context "when upgrading from -EAP to final version" do
            let(:dependency_version) { "1.0.0-EAP-1" }

            it { is_expected.to be true }
          end

          context "when upgrading from -PRERELEASE to final version" do
            let(:dependency_version) { "1.0.0-PRERELEASE" }

            it { is_expected.to be true }
          end

          context "when upgrading from -EXPERIMENTAL to final version" do
            let(:dependency_version) { "1.0.0-EXPERIMENTAL" }

            it { is_expected.to be true }
          end
        end

        context "when upgrading from snapshot versions" do
          context "when upgrading from -SNAPSHOT to final version" do
            let(:dependency_version) { "1.0.0-SNAPSHOT" }

            it { is_expected.to be true }
          end
        end
      end

      context "when upgrading from a released version to a pre-release" do
        let(:dependency_version) { "1.0.0" }

        context "when upgrading to release candidate–like versions" do
          context "when upgrading to -cr" do
            let(:comparison_version) { "1.0.1-cr" }

            it { is_expected.to be false }
          end

          context "when upgrading to -rc" do
            let(:comparison_version) { "1.0.1-rc" }

            it { is_expected.to be false }
          end
        end

        context "when upgrading to early-stage versions" do
          context "when upgrading to -alpha" do
            let(:comparison_version) { "1.0.1-alpha" }

            it { is_expected.to be false }
          end

          context "when upgrading to -beta" do
            let(:comparison_version) { "1.0.1-beta" }

            it { is_expected.to be false }
          end

          context "when upgrading to -milestone" do
            let(:comparison_version) { "1.0.2-M1" }

            it { is_expected.to be false }
          end
        end

        context "when upgrading to development and experimental versions" do
          context "when upgrading to -dev" do
            let(:comparison_version) { "1.0.1-dev" }

            it { is_expected.to be false }
          end

          context "when upgrading to -EA" do
            let(:comparison_version) { "1.0.2-EA" }

            it { is_expected.to be false }
          end

          context "when upgrading to -EAP" do
            let(:comparison_version) { "1.0.1-EAP" }

            it { is_expected.to be false }
          end

          context "when upgrading to -PRERELEASE" do
            let(:comparison_version) { "1.0.1-PRERELEASE" }

            it { is_expected.to be false }
          end

          context "when upgrading to -EXPERIMENTAL" do
            let(:comparison_version) { "1.0.1-EXPERIMENTAL" }

            it { is_expected.to be false }
          end
        end
      end

      context "when using special Maven release qualifiers" do
        context "when using RELEASE qualifiers" do
          context "when the suffix is -RELEASE" do
            let(:dependency_version) { "1.0.0-RELEASE" }
            let(:comparison_version) { "2.0.0" }

            it { is_expected.to be true }
          end

          context "when the suffix is -Release (case-insensitive)" do
            let(:dependency_version) { "1.0.0-Release" }
            let(:comparison_version) { "2.0.0" }

            it { is_expected.to be true }
          end
        end

        context "when using FINAL and GA qualifiers" do
          context "when the suffix is -FINAL" do
            let(:dependency_version) { "1.0.0-FINAL" }
            let(:comparison_version) { "2.0.0" }

            it { is_expected.to be true }
          end

          context "when the suffix is -GA" do
            let(:dependency_version) { "1.0.0-GA" }
            let(:comparison_version) { "2.0.0" }

            it { is_expected.to be true }
          end

          context "when transitioning from FINAL to GA" do
            let(:dependency_version) { "1.0.0-FINAL" }
            let(:comparison_version) { "2.0.0-GA" }

            it { is_expected.to be true }
          end
        end
      end

      context "when common Maven release suffixes exist" do
        context "when using platform-specific release qualifiers" do
          context "when the suffix is -jre" do
            let(:dependency_version) { "1.2.3-jre" }
            let(:comparison_version) { "1.2.4-jre" }

            it { is_expected.to be true }
          end

          context "when the suffix is -android" do
            let(:dependency_version) { "1.2.3-android" }
            let(:comparison_version) { "1.2.4-android" }

            it { is_expected.to be true }
          end
        end

        context "when using native classifier variations" do
          context "when the version uses hyphenated -mt suffix" do
            let(:dependency_version) { "native-mt" }
            let(:comparison_version) { "native_mt" }

            it { is_expected.to be true }
          end

          context "when the version uses underscored _mt suffix" do
            let(:dependency_version) { "native_mt" }
            let(:comparison_version) { "native-mt" }

            it { is_expected.to be true }
          end
        end

        describe "when JRE/JDK version qualifiers are used" do
          context "when both versions are identical JREs" do
            let(:dependency_version) { "13.2.1.jre8" }
            let(:comparison_version) { "13.2.1.jre8" }

            it { is_expected.to be true }
          end

          context "when both versions are identical JREs(case insensitive)" do
            let(:dependency_version) { "13.2.1.JRE8" }
            let(:comparison_version) { "13.2.1.jre8" }

            it { is_expected.to be true }
          end

          context "when both versions are identical JDKs" do
            let(:dependency_version) { "1.0.0-jdk11" }
            let(:comparison_version) { "1.0.0-jdk11" }

            it { is_expected.to be true }
          end

          context "when upgrading from JRE to JDK (same major version)" do
            let(:dependency_version) { "2.1.0.jre11" }
            let(:comparison_version) { "2.1.0.jdk11" }

            it { is_expected.to be true }
          end

          context "when downgrading from JDK to JRE (forbidden capability loss)" do
            # This would remove the compiler/tools from a library that might need them
            let(:dependency_version) { "2.1.0.jdk11" }
            let(:comparison_version) { "2.1.0.jre11" }

            it { is_expected.to be false }
          end

          context "when the Java major versions do not match" do
            # Even if both are JREs, the java version mismatch is a failure
            let(:dependency_version) { "13.2.1.jre8" }
            let(:comparison_version) { "13.2.1.jre11" }

            it { is_expected.to be false }
          end

          context "when the comparison version is missing a suffix" do
            let(:dependency_version) { "13.2.1.jre8" }
            let(:comparison_version) { "13.2.1" }

            it { is_expected.to be false }
          end

          context "when the current version is missing the suffix" do
            let(:dependency_version) { "13.2.1" }
            let(:comparison_version) { "13.2.1-jre" }

            it { is_expected.to be false }
          end

          context "when using vendor-specific version strings (e.g., Guava style)" do
            let(:dependency_version) { "33.0.0-jre" }
            let(:comparison_version) { "33.0.0-jre" }

            it { is_expected.to be true }
          end
        end
      end

      context "when the dependency version uses git commit for the delimiter" do
        # Some tests are based on real-world examples from Jenkin's plugin release conventions
        # See
        # https://www.jenkins.io/doc/developer/publishing/releasing-cd/
        # https://github.com/jenkinsci/jep/blob/master/jep/229/README.adoc

        context "when the version contains embedded git commits" do
          let(:dependency_version) { "6.2108.v08c2b_01b_cf4d" }
          let(:comparison_version) { "6.2122.v70b_7b_f659d72" }

          it { is_expected.to be true }
        end

        context "when the version has a single version with embedded git commit" do
          let(:dependency_version) { "5622.c9c3051619f5" }
          let(:comparison_version) { "5681.79d2ddf61465" }

          it { is_expected.to be true }
        end

        context "when version has semantic version with git SHA and build number" do
          # Format: {semver}-{build}.v{gitsha}
          # Example from https://plugins.jenkins.io/caffeine-api/
          let(:dependency_version) { "2.9.2-29.v717aac953ff3" }
          let(:comparison_version) { "2.9.3-30.va1b2c3d4e5f6" }

          it { is_expected.to be true }
        end

        context "when version has four-digit revision with git SHA" do
          # Format: {revision}.v{gitsha}
          # Example from credentials plugin
          let(:dependency_version) { "1074.v60e6c29b_b_44b_" }
          let(:comparison_version) { "1087.1089.v2f1b_9a_b_040e4" }

          it { is_expected.to be true }
        end

        context "when version has multi-part revision with git SHA" do
          # Format: {major}.{revision}.v{gitsha}
          # Example from credentials plugin
          let(:dependency_version) { "1087.1089.v2f1b_9a_b_040e4" }
          let(:comparison_version) { "1087.v16065d268466" }

          it { is_expected.to be true }
        end

        context "when version has three-digit build with git SHA" do
          # Format: {build}.v{gitsha}
          # Example from jackson2-api plugin
          let(:dependency_version) { "230.v59243c64b0a5" }
          let(:comparison_version) { "246.va8a9f3eaf46a" }

          it { is_expected.to be true }
        end

        context "when version has longer multi-part format" do
          # Format: {major}.{minor}.{patch}.{build}.v{gitsha}
          # Example from https://plugins.jenkins.io/aws-java-sdk/
          let(:dependency_version) { "1.12.163-315.v2b_716ec8e4df" }
          let(:comparison_version) { "1.12.170-320.v3c4d5e6f7g8h" }

          it { is_expected.to be true }
        end

        context "when comparing standard semver to incremental format" do
          # One uses standard semver, the other uses JEP-229
          let(:dependency_version) { "2.6.1" }
          let(:comparison_version) { "1087.v16065d268466" }

          it { is_expected.to be false }
        end

        context "when both versions have different delimiter styles in git SHA" do
          # Both have git SHAs but different underscore patterns
          let(:dependency_version) { "100.v60e6c29b_b_44b_" }
          let(:comparison_version) { "105.va_b_018a_a_6b_0d3" }

          it { is_expected.to be true }
        end

        context "when the version has a short git commit" do
          let(:dependency_version) { "5622.c9c3051" }
          let(:comparison_version) { "5681.c9c3051" }

          it { is_expected.to be true }
        end

        context "when the version has a mix of short and long git commits" do
          let(:dependency_version) { "5622.c9c3051" }
          let(:comparison_version) { "5681.c9c3051619f5" }

          it { is_expected.to be true }
        end

        context "when the version has a single embedded git commit using different delimiters" do
          let(:dependency_version) { "5622-c9c3051619f5" }
          let(:comparison_version) { "5681.79d2ddf61465" }

          it { is_expected.to be true }
        end

        context "when the version has a single embedded git commit with the v suffix" do
          # Example: https://github.com/jenkinsci/bom/releases/tag/5622.vc9c3051619f5
          let(:dependency_version) { "5622.vc9c3051619f5" }
          let(:comparison_version) { "5681.79d2ddf61465" }

          it { is_expected.to be true }
        end

        context "when the version contains embedded git commit with a delimiter and leading character" do
          # Example: https://github.com/jenkinsci/bom/releases/tag/5723.v6f9c6b_d1218a_
          let(:dependency_version) { "5723.v6f9c6b_d1218a_" }
          let(:comparison_version) { "5622.c9c3051619f5" }

          it { is_expected.to be true }
        end

        context "when only one of the version contains embedded git commits" do
          let(:dependency_version) { "5933.vcf06f7b_5d1a_2" }
          let(:comparison_version) { "5933" }

          it { is_expected.to be false }
        end

        context "when version has pre-release qualifier with git SHA" do
          # Format: {number}.v{git-sha}-{qualifier}
          let(:dependency_version) { "252.v356d312df76f-beta" }
          let(:comparison_version) { "252.v456e423eg87g-beta" }

          it { is_expected.to be true }
        end

        context "when upgrading from pre-release to stable with git SHA" do
          let(:dependency_version) { "252.v356d312df76f-beta" }
          let(:comparison_version) { "252.v456e423eg87g" }

          it { is_expected.to be true }
        end

        context "when downgrading from stable to pre-release with git SHA" do
          let(:dependency_version) { "252.v456e423eg87g" }
          let(:comparison_version) { "252.v356d312df76f-beta" }

          it { is_expected.to be false }
        end

        context "when git SHA has maximum length (40 chars)" do
          let(:dependency_version) { "100.va1b2c3d4e5f6789012345678901234567890" }
          let(:comparison_version) { "200.vb2c3d4e5f67890123456789012345678901" }

          it { is_expected.to be true }
        end

        context "when git SHA has minimum length (7 chars)" do
          let(:dependency_version) { "100.va1b2c3d" }
          let(:comparison_version) { "200.vb2c3d4e" }

          it { is_expected.to be true }
        end

        context "when one version has git SHA and other is standard semver" do
          let(:dependency_version) { "1.2.3" }
          let(:comparison_version) { "1.2.4.va1b2c3d" }

          it { is_expected.to be false }
        end

        context "when git SHA portion is invalid (too short)" do
          let(:dependency_version) { "100-vabc" }
          let(:comparison_version) { "200-vdef" }

          # These should NOT be treated as git SHAs
          it { is_expected.to be false }
        end

        context "when version has RC progression with git SHAs" do
          let(:dependency_version) { "100.va1b2c3d-rc1" }
          let(:comparison_version) { "100.ve5f6g7h-rc2" }

          it { is_expected.to be true }
        end

        context "when version is numbers only it should be considered a sha" do
          # Tightening the regex to avoid false positives is important,
          let(:dependency_version) { "100.va122334" }
          let(:comparison_version) { "100.va232435" }

          it { is_expected.to be true }
        end
      end

      context "when the dependency versions uses dates for the delimiter" do
        context "when the date is dot separated" do
          let(:dependency_version) { "2025.12.16.05.04" }
          let(:comparison_version) { "2026.12.16.05.06" }

          it { is_expected.to be true }
        end

        context "when the date is dash separated" do
          let(:dependency_version) { "2025-12-16-05-04" }
          let(:comparison_version) { "2026-12-16-05-06" }

          it { is_expected.to be true }
        end

        context "when the date is compact YYYYMMDD" do
          let(:dependency_version) { "20251216" }
          let(:comparison_version) { "20261216" }

          it { is_expected.to be true }
        end

        context "when the date is compact YYYYMMDD delimiter" do
          let(:dependency_version) { "1.0-20251216" }
          let(:comparison_version) { "1.0-20261216" }

          it { is_expected.to be true }
        end

        context "when the date is embedded in a version string" do
          let(:dependency_version) { "1.0.0-2025_12_16_05_04" }
          let(:comparison_version) { "1.0.0-2026_12_16_05_06" }

          it { is_expected.to be true }
        end

        context "when the date has single digit month/day" do
          let(:dependency_version) { "2025_1_6_05_04" }
          let(:comparison_version) { "2026_1_6_05_06" }

          it { is_expected.to be true }
        end

        context "when the version contains no date" do
          let(:dependency_version) { "1.2.3-2025_1_6_05_04" }
          let(:comparison_version) { "2.0.0-beta" }

          it { is_expected.to be false }
        end

        context "when date appears with prefix and suffix text" do
          let(:dependency_version) { "release-2025_12_16_05_04-hotfix" }
          let(:comparison_version) { "release-2026_12_16_05_06-hotfix" }

          it { is_expected.to be true }
        end
      end
    end
  end
end
