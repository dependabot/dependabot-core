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
      end
    end
  end
end
