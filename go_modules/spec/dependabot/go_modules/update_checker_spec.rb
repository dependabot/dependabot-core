# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/go_modules/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::GoModules::UpdateChecker do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: github_credentials,
      security_advisories: security_advisories,
      ignored_versions: []
    )
  end

  let(:security_advisories) { [] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "go_modules"
    )
  end
  let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-lib" }
  let(:dependency_version) { "1.0.0" }
  let(:requirements) do
    [{
      file: "go.mod",
      requirement: dependency_version,
      groups: [],
      source: { type: "default", source: dependency_name }
    }]
  end
  let(:go_mod_content) do
    <<~GOMOD
      module foobar
      require #{dependency_name} v#{dependency_version}
    GOMOD
  end
  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "go.mod",
        content: go_mod_content
      )
    ]
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    context "when a supported newer version is available" do
      it "updates to the newer version" do
        is_expected.to eq(Dependabot::GoModules::Version.new("1.1.0"))
      end
    end

    context "updates indirect dependencies" do
      let(:requirements) { [] }

      it "updates to the newer version" do
        is_expected.to eq(Dependabot::GoModules::Version.new("1.1.0"))
      end
    end

    it "updates v2+ modules"
    it "doesn't update to v2+ modules with un-versioned paths"
    it "updates modules that don't live at a repository root"
    it "updates Git SHAs to releases that include them"
    it "doesn't updates Git SHAs to releases that don't include them"
    it "doesn't update Git SHAs not on master to newer commits to master"
  end

  describe "#lowest_security_fix_version" do
    subject(:lowest_security_fix_version) { checker.lowest_security_fix_version }

    let(:dependency_version) { "1.0.1" }

    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "go_modules",
          vulnerable_versions: ["= 1.0.1"]
        )
      ]
    end

    context "when a supported newer version is available" do
      it "updates to the least new supported version" do
        is_expected.to eq(Dependabot::GoModules::Version.new("1.0.5"))
      end
    end
  end

  describe "#lowest_resolvable_security_fix_version" do
    subject(:lowest_resolvable_security_fix_version) { checker.lowest_resolvable_security_fix_version }

    let(:dependency_version) { "1.0.1" }

    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "go_modules",
          vulnerable_versions: ["= 1.0.1"]
        )
      ]
    end

    context "when a supported newer version is available" do
      it "updates to the least new supported version" do
        is_expected.to eq(Dependabot::GoModules::Version.new("1.0.5"))
      end
    end

    context "updates indirect dependencies" do
      let(:requirements) { [] }

      it "updates to the least new supported version" do
        is_expected.to eq(Dependabot::GoModules::Version.new("1.0.5"))
      end
    end

    context "when the current version is not vulnerable" do
      let(:dependency_version) { "1.0.0" }

      it "raises an error " do
        expect { lowest_resolvable_security_fix_version.to }.to raise_error(RuntimeError) do |error|
          expect(error.message).to eq("Dependency not vulnerable!")
        end
      end
    end
  end
end
