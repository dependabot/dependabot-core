# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/update_checkers/base"

RSpec.describe Dependabot::UpdateCheckers::Base do
  let(:updater_instance) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
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
      package_manager: "bundler"
    )
  end
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
  before do
    allow(updater_instance).
      to receive(:latest_version).
      and_return(latest_version)

    allow(updater_instance).
      to receive(:latest_resolvable_version).
      and_return(latest_resolvable_version)

    allow(updater_instance).
      to receive(:latest_resolvable_version_with_no_unlock).
      and_return(latest_resolvable_version_with_no_unlock)

    allow(updater_instance).
      to receive(:updated_requirements).
      and_return(updated_requirements)
  end

  describe "#up_to_date?" do
    subject(:up_to_date) { updater_instance.up_to_date? }

    context "when the dependency is outdated" do
      let(:latest_version) { Gem::Version.new("1.6.0") }

      it { is_expected.to be_falsey }

      context "but cannot resolve to the new version" do
        let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }
        it { is_expected.to be_falsey }
      end

      context "but is switching to a git source" do
        let(:latest_resolvable_version) { "a" * 40 }
        it { is_expected.to be_falsey }
      end
    end

    context "when the dependency is up-to-date" do
      let(:latest_version) { Gem::Version.new("1.5.0") }
      it { is_expected.to be_truthy }

      it "doesn't attempt to resolve the dependency" do
        expect(updater_instance).to_not receive(:latest_resolvable_version)
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
          version: "5bfb6d149c410801f194da7ceb3b2bdc5e8b75f3",
          requirements: [
            { file: "Gemfile", requirement: ">= 0", groups: [], source: nil }
          ],
          package_manager: "bundler"
        )
      end

      context "that matches the latest version" do
        let(:latest_version) { "5bfb6d149c410801f194da7ceb3b2bdc5e8b75f3" }
        it { is_expected.to be_truthy }
      end

      context "that does not match the latest version" do
        let(:latest_version) { "4bfb6d149c410801f194da7ceb3b2bdc5e8b75f3" }
        it { is_expected.to eq(false) }

        context "but the latest latest_resolvable_version does" do
          let(:latest_resolvable_version) do
            "5bfb6d149c410801f194da7ceb3b2bdc5e8b75f3"
          end
          it { is_expected.to eq(false) }
        end
      end
    end

    context "when updating a requirement file" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          requirements: requirements,
          package_manager: "bundler"
        )
      end
      let(:requirements) do
        [{ file: "Gemfile", requirement: "~> 1", groups: [], source: nil }]
      end

      context "that already permits the latest version" do
        let(:updated_requirements) { requirements }
        it { is_expected.to be_truthy }
      end

      context "that doesn't yet permit the latest version" do
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

      context "that we don't know how to fix" do
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
            package_manager: "bundler"
          )
        end
        it { is_expected.to be_falsey }
      end

      context "when the dependency is up-to-date" do
        let(:latest_version) { Gem::Version.new("1.5.0") }
        it { is_expected.to be_falsey }

        it "doesn't attempt to resolve the dependency" do
          expect(updater_instance).to_not receive(:latest_resolvable_version)
          expect(updater_instance).
            to_not receive(:latest_resolvable_version_with_no_unlock)
          can_update
        end
      end

      context "when the dependency is outdated" do
        let(:latest_version) { Gem::Version.new("1.6.0") }

        context "and can't resolve to the new version without an unlock" do
          let(:latest_resolvable_version) { Gem::Version.new("1.6.0") }
          let(:latest_resolvable_version_with_no_unlock) do
            Gem::Version.new("1.5.0")
          end

          it { is_expected.to be_falsey }
        end

        context "and can resolve to the new version without an unlock" do
          let(:latest_resolvable_version) { Gem::Version.new("1.6.0") }
          let(:latest_resolvable_version_with_no_unlock) do
            Gem::Version.new("1.6.0")
          end

          it { is_expected.to be_truthy }
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
          expect(updater_instance).to_not receive(:latest_resolvable_version)
          expect(updater_instance).
            to_not receive(:latest_version_resolvable_with_full_unlock?)
          can_update
        end
      end

      context "when the dependency is outdated" do
        let(:latest_version) { Gem::Version.new("1.6.0") }

        context "and cannot resolve to the new version" do
          let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }

          context "even with a full unlock" do
            before do
              allow(updater_instance).
                to receive(:latest_version_resolvable_with_full_unlock?).
                and_return(false)
            end
            it { is_expected.to be_falsey }
          end

          context "but can with a full unlock" do
            before do
              allow(updater_instance).
                to receive(:latest_version_resolvable_with_full_unlock?).
                and_return(true)
            end
            it { is_expected.to be_truthy }
          end
        end
      end
    end

    context "when the dependency is outdated" do
      let(:latest_version) { Gem::Version.new("1.6.0") }

      it { is_expected.to be_truthy }

      context "but cannot resolve to the new version" do
        let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }
        it { is_expected.to be_falsey }
      end
    end

    context "when the dependency is up-to-date" do
      let(:latest_version) { Gem::Version.new("1.5.0") }
      it { is_expected.to be_falsey }

      it "doesn't attempt to resolve the dependency" do
        expect(updater_instance).to_not receive(:latest_resolvable_version)
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
          requirements: [
            { file: "Gemfile", requirement: ">= 0", groups: [], source: nil }
          ],
          package_manager: "bundler"
        )
      end

      context "that matches the latest version" do
        let(:latest_version) { "5bfb6d149c410801f194da7ceb3b2bdc5e8b75f3" }
        it { is_expected.to be_falsey }
      end

      context "that does not match the latest version" do
        let(:latest_version) { "4bfb6d149c410801f194da7ceb3b2bdc5e8b75f3" }
        it { is_expected.to eq(true) }

        context "but the latest latest_resolvable_version does" do
          let(:latest_resolvable_version) do
            "5bfb6d149c410801f194da7ceb3b2bdc5e8b75f3"
          end
          it { is_expected.to eq(false) }
        end
      end
    end

    context "when updating a requirement file" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          requirements: requirements,
          package_manager: "bundler"
        )
      end
      let(:requirements) do
        [{ file: "Gemfile", requirement: "~> 1", groups: [], source: nil }]
      end

      context "that already permits the latest version" do
        let(:updated_requirements) { requirements }
        it { is_expected.to be_falsey }
      end

      context "that doesn't yet permit the latest version" do
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

      context "that we don't know how to fix" do
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
    let(:latest_resolvable_version_with_no_unlock) { Gem::Version.new("1.7.0") }

    its(:count) { is_expected.to eq(1) }

    describe "the dependency" do
      subject { updated_dependencies.first }
      its(:version) { is_expected.to eq("1.8.0") }
      its(:previous_version) { is_expected.to eq("1.5.0") }
      its(:package_manager) { is_expected.to eq(dependency.package_manager) }
      its(:name) { is_expected.to eq(dependency.name) }
      its(:requirements) { is_expected.to eq(updated_requirements) }
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
    end
  end
end
