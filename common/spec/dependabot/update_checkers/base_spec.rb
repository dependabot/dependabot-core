# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/security_advisory"
require "dependabot/update_checkers/base"

RSpec.describe Dependabot::UpdateCheckers::Base do
  let(:updater_instance) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      ignored_versions: ignored_versions,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      requirements: original_requirements,
      package_manager: "dummy"
    )
  end
  let(:ignored_versions) { [] }
  let(:latest_version) { Gem::Version.new("1.0.0") }
  let(:original_requirements) do
    [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
  end
  let(:updated_requirements) do
    [{
      file: "Gemfile",
      requirement: updated_requirement,
      groups: [],
      source: nil
    }]
  end
  let(:updated_requirement) { ">= 1.0.0" }
  let(:latest_resolvable_version) { latest_version }
  let(:latest_resolvable_version_with_no_unlock) { latest_version }
  let(:latest_resolvable_previous_version) { dependency.version }

  before do
    allow(updater_instance)
      .to receive_messages(latest_version: latest_version, latest_resolvable_version: latest_resolvable_version,
                           latest_resolvable_version_with_no_unlock: latest_resolvable_version_with_no_unlock,
                           latest_resolvable_previous_version: latest_resolvable_previous_version,
                           updated_requirements: updated_requirements)
  end

  describe "#up_to_date?" do
    subject(:up_to_date) { updater_instance.up_to_date? }

    context "when the dependency is outdated" do
      let(:latest_version) { Gem::Version.new("1.6.0") }

      it { is_expected.to be_falsey }

      context "when unable to resolve to the new version" do
        let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }

        it { is_expected.to be_falsey }
      end

      context "when switching to a git source" do
        let(:latest_resolvable_version) { "a" * 40 }

        it { is_expected.to be_falsey }
      end
    end

    context "when the dependency is up-to-date" do
      let(:latest_version) { Gem::Version.new("1.5.0") }

      it { is_expected.to be_truthy }

      it "doesn't attempt to resolve the dependency" do
        expect(updater_instance).not_to receive(:latest_resolvable_version)
        up_to_date
      end
    end

    context "when the dependency couldn't be found" do
      let(:latest_version) { nil }

      it { is_expected.to be_falsey }
    end

    context "when the dependency has a SHA-1 hash version" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          version: dependency_version,
          requirements:
            [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }],
          package_manager: "dummy"
        )
      end
      let(:dependency_version) { "5bfb6d149c410801f194da7ceb3b2bdc5e8b75f3" }

      context "when matching the latest version" do
        let(:latest_version) { "5bfb6d149c410801f194da7ceb3b2bdc5e8b75f3" }

        it { is_expected.to be_truthy }
      end

      context "when not matching the latest version" do
        let(:latest_version) { "4bfb6d149c410801f194da7ceb3b2bdc5e8b75f3" }

        it { is_expected.to be(false) }

        context "when the latest latest_resolvable_version does" do
          let(:latest_resolvable_version) do
            "5bfb6d149c410801f194da7ceb3b2bdc5e8b75f3"
          end

          it { is_expected.to be(false) }
        end
      end

      context "when dealing with only a substring" do
        let(:dependency_version) { "5bfb6d1" }

        context "when matching the latest version" do
          let(:latest_version) { "5bfb6d149c410801f194da7ceb3b2bdc5e8b75f3" }

          it { is_expected.to be_truthy }
        end

        context "when not matching the latest version" do
          let(:latest_version) { "4bfb6d149c410801f194da7ceb3b2bdc5e8b75f3" }

          it { is_expected.to be(false) }

          context "when the latest resolvable version does" do
            let(:latest_resolvable_version) do
              "5bfb6d149c410801f194da7ceb3b2bdc5e8b75f3"
            end

            it { is_expected.to be(false) }
          end
        end
      end
    end

    context "when updating a requirement file" do
      let(:latest_version) { Gem::Version.new("4.0.0") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          requirements: requirements,
          package_manager: "dummy"
        )
      end
      let(:requirements) do
        [{ file: "Gemfile", requirement: "~> 1", groups: [], source: nil }]
      end

      context "when the requirement is out of date" do
        let(:updated_requirements) { requirements }

        it { is_expected.to be_falsy }
      end

      context "when not permitting the latest version" do
        let(:updated_requirements) do
          [{
            file: "Gemfile",
            requirement: ">= 1, < 3",
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to be_falsey }
      end

      context "when the latest version is a downgrade" do
        let(:latest_version) { Gem::Version.new("0.5.0") }

        it { is_expected.to be_truthy }
      end

      context "when dealing with an issue we don't know to fix" do
        let(:updated_requirements) do
          [{
            file: "Gemfile",
            requirement: :unfixable,
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to be_falsey }
      end
    end
  end

  describe "#can_update?" do
    subject(:can_update) do
      updater_instance.can_update?(requirements_to_unlock: :own)
    end

    context "with no requirements unlocked" do
      subject(:can_update) do
        updater_instance.can_update?(requirements_to_unlock: :none)
      end

      context "when the dependency is not in the lockfile" do
        let(:latest_version) { Gem::Version.new("7.5.0") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: nil,
            requirements: original_requirements,
            package_manager: "dummy"
          )
        end

        it { is_expected.to be_falsey }
      end

      context "when the dependency is up-to-date" do
        let(:latest_version) { Gem::Version.new("1.5.0") }

        it { is_expected.to be_falsey }

        it "doesn't attempt to resolve the dependency" do
          expect(updater_instance).not_to receive(:latest_resolvable_version)
          expect(updater_instance)
            .not_to receive(:latest_resolvable_version_with_no_unlock)
          can_update
        end
      end

      context "when the dependency is outdated" do
        let(:latest_version) { Gem::Version.new("1.6.0") }

        context "when unable to resolve to the new version without an unlock" do
          let(:latest_resolvable_version) { Gem::Version.new("1.6.0") }
          let(:latest_resolvable_version_with_no_unlock) do
            Gem::Version.new("1.5.0")
          end

          it { is_expected.to be_falsey }
        end

        context "when able to resolve to the new version without an unlock" do
          let(:latest_resolvable_version) { Gem::Version.new("1.6.0") }
          let(:latest_resolvable_version_with_no_unlock) do
            Gem::Version.new("1.6.0")
          end

          it { is_expected.to be_truthy }

          context "when all versions are being ignored" do
            let(:updater_instance) do
              described_class.new(
                dependency: dependency,
                dependency_files: [],
                ignored_versions: [">= 0"],
                credentials: [{
                  "type" => "git_source",
                  "host" => "github.com",
                  "username" => "x-access-token",
                  "password" => "token"
                }]
              )
            end

            it { is_expected.to be_falsey }
          end
        end
      end
    end

    context "with all requirements unlocked" do
      subject(:can_update) do
        updater_instance.can_update?(requirements_to_unlock: :all)
      end

      context "when the dependency is up-to-date" do
        let(:latest_version) { Gem::Version.new("1.5.0") }

        it { is_expected.to be_falsey }

        it "doesn't attempt to resolve the dependency" do
          expect(updater_instance).not_to receive(:latest_resolvable_version)
          expect(updater_instance)
            .not_to receive(:latest_version_resolvable_with_full_unlock?)
          can_update
        end
      end

      context "when the dependency is outdated" do
        let(:latest_version) { Gem::Version.new("1.6.0") }

        context "when unable to resolve to the new version" do
          let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }

          context "when possible with a full unlock" do
            before do
              allow(updater_instance)
                .to receive(:latest_version_resolvable_with_full_unlock?)
                .and_return(false)
            end

            it { is_expected.to be_falsey }
          end

          context "when the requirements can be updated with a full unlock" do
            before do
              allow(updater_instance)
                .to receive(:latest_version_resolvable_with_full_unlock?)
                .and_return(true)
            end

            it { is_expected.to be_truthy }
          end
        end
      end
    end

    context "when the dependency is outdated" do
      let(:latest_version) { Gem::Version.new("1.6.0") }

      it { is_expected.to be_truthy }

      context "when unable to resolve to the new version" do
        let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }

        it { is_expected.to be_falsey }
      end

      context "when unable to unlock the requirement" do
        let(:updated_requirements) do
          [{
            file: "Gemfile",
            requirement: :unfixable,
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to be_falsey }
      end
    end

    context "when the dependency is up-to-date" do
      let(:latest_version) { Gem::Version.new("1.5.0") }

      it { is_expected.to be_falsey }

      it "doesn't attempt to resolve the dependency" do
        expect(updater_instance).not_to receive(:latest_resolvable_version)
        can_update
      end
    end

    context "when the dependency couldn't be found" do
      let(:latest_version) { nil }

      it { is_expected.to be_falsey }
    end

    context "when the dependency has a SHA-1 hash version" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          version: "5bfb6d149c410801f194da7ceb3b2bdc5e8b75f3",
          requirements:
            [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }],
          package_manager: "dummy"
        )
      end

      context "when matching the latest version" do
        let(:latest_version) { "5bfb6d149c410801f194da7ceb3b2bdc5e8b75f3" }

        it { is_expected.to be_falsey }
      end

      context "when not matching the latest version" do
        let(:latest_version) { "4bfb6d149c410801f194da7ceb3b2bdc5e8b75f3" }

        it { is_expected.to be(true) }

        context "when the latest latest_resolvable_version does" do
          let(:latest_resolvable_version) do
            "5bfb6d149c410801f194da7ceb3b2bdc5e8b75f3"
          end

          it { is_expected.to be(false) }
        end
      end
    end

    context "when updating a requirement file" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          requirements: requirements,
          package_manager: "dummy"
        )
      end
      let(:requirements) do
        [{ file: "Gemfile", requirement: "~> 1", groups: [], source: nil }]
      end

      context "when already permits the latest version" do
        let(:updated_requirements) { requirements }

        it { is_expected.to be_falsey }
      end

      context "when not permitting the latest version" do
        let(:updated_requirements) do
          [{
            file: "Gemfile",
            requirement: ">= 1, < 3",
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to be_truthy }
      end

      context "when dealing with an issue we don't know how to fix" do
        let(:updated_requirements) do
          [{
            file: "Gemfile",
            requirement: :unfixable,
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to be_falsey }
      end
    end
  end

  describe "#updated_dependencies" do
    subject(:updated_dependencies) do
      updater_instance.updated_dependencies(requirements_to_unlock: :own)
    end

    let(:latest_version) { Gem::Version.new("1.9.0") }
    let(:latest_resolvable_version) { Gem::Version.new("1.8.0") }
    let(:latest_resolvable_version_with_no_unlock) { "1.7.0" }

    its(:count) { is_expected.to eq(1) }

    describe "the dependency" do
      subject { updated_dependencies.first }

      its(:version) { is_expected.to eq("1.8.0") }
      its(:previous_version) { is_expected.to eq("1.5.0") }
      its(:package_manager) { is_expected.to eq(dependency.package_manager) }
      its(:name) { is_expected.to eq(dependency.name) }
      its(:requirements) { is_expected.to eq(updated_requirements) }
    end

    context "without a previous version" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          version: nil,
          requirements: original_requirements,
          package_manager: "dummy"
        )
      end

      describe "the dependency" do
        subject { updated_dependencies.first }

        its(:version) { is_expected.to eq("1.8.0") }
        its(:previous_version) { is_expected.to be_nil }
      end

      context "when resolved from a requirement" do
        let(:latest_resolvable_previous_version) { "1.4.0" }

        describe "the dependency" do
          subject { updated_dependencies.first }

          its(:version) { is_expected.to eq("1.8.0") }
          its(:previous_version) { is_expected.to eq("1.4.0") }
        end
      end
    end

    context "when not updating requirements" do
      subject(:updated_dependencies) do
        updater_instance.updated_dependencies(requirements_to_unlock: :none)
      end

      its(:count) { is_expected.to eq(1) }

      describe "the dependency" do
        subject { updated_dependencies.first }

        its(:version) { is_expected.to eq("1.7.0") }
        its(:previous_version) { is_expected.to eq("1.5.0") }
        its(:package_manager) { is_expected.to eq(dependency.package_manager) }
        its(:name) { is_expected.to eq(dependency.name) }
        its(:requirements) { is_expected.to eq(original_requirements) }
      end

      context "without a previous version" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: nil,
            requirements: original_requirements,
            package_manager: "dummy"
          )
        end

        describe "the dependency" do
          subject { updated_dependencies.first }

          it { is_expected.to be_nil }
        end
      end
    end
  end

  describe "#vulnerable?" do
    subject(:vulnerable) { updater_instance.send(:vulnerable?) }

    let(:updater_instance) do
      described_class.new(
        dependency: dependency,
        dependency_files: [],
        security_advisories: security_advisories,
        credentials: [{
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }]
      )
    end
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "business",
        version: version,
        requirements: original_requirements,
        package_manager: "dummy"
      )
    end

    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: "rails",
          package_manager: "dummy",
          vulnerable_versions: ["~> 0.5", "~> 1.0"],
          safe_versions: ["> 1.5.1"]
        )
      ]
    end
    let(:version) { "1.5.1" }

    context "with a safe version" do
      let(:version) { "1.5.2" }

      it { is_expected.to be(false) }
    end

    context "with a vulnerable version" do
      let(:version) { "1.5.1" }

      it { is_expected.to be(true) }
    end

    context "with no vulnerabilities" do
      let(:security_advisories) { [] }

      it { is_expected.to be(false) }
    end

    context "with only safe versions" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "rails",
            package_manager: "dummy",
            safe_versions: ["> 1.5.1"]
          )
        ]
      end

      context "with a vulnerable version" do
        let(:version) { "1.5.1" }

        it { is_expected.to be(true) }
      end

      context "with a safe version" do
        let(:version) { "1.5.2" }

        it { is_expected.to be(false) }
      end
    end

    context "with only vulnerable versions" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "rails",
            package_manager: "dummy",
            vulnerable_versions: ["<= 1.5.1"]
          )
        ]
      end

      context "with a vulnerable version" do
        let(:version) { "1.5.1" }

        it { is_expected.to be(true) }
      end

      context "with a safe version" do
        let(:version) { "1.5.2" }

        it { is_expected.to be(false) }
      end
    end

    context "with no details" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "rails",
            package_manager: "dummy"
          )
        ]
      end

      it { is_expected.to be(false) }
    end
  end

  describe "#ignore_requirements" do
    subject(:ignore_requirements) { updater_instance.ignore_requirements }

    it { is_expected.to eq([]) }

    context "with ignored versions" do
      let(:ignored_versions) { ["~> 1.0, < 2"] }

      it { is_expected.to eq([updater_instance.requirement_class.new("~> 1.0", "< 2")]) }
    end
  end
end
