# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/go/modules"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Go::Modules do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: github_credentials,
      ignored_versions: ignored_versions
    )
  end
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
      source: source
    }]
  end
  let(:source) { { type: "default", source: dependency_name } }
  let(:ignored_versions) { [] }
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

    it "updates minor (but not major) semver versions" do
      expect(latest_resolvable_version).
        to eq(Dependabot::Utils::Go::Version.new("1.1.0"))
    end

    it "doesn't update major semver versions" do
      expect(latest_resolvable_version).
        to_not eq(Dependabot::Utils::Go::Version.new("2.0.0"))
    end

    context "with a go.mod excluded version" do
      let(:go_mod_content) do
        <<~GOMOD
          module foobar
          require #{dependency_name} v#{dependency_version}
          exclude #{dependency_name} v1.1.0
        GOMOD
      end

      it "doesn't update to the excluded version" do
        expect(latest_resolvable_version).
          to eq(Dependabot::Utils::Go::Version.new("1.0.1"))
      end
    end

    it "doesn't update to (Dependabot) ignored versions" do
      # TODO: let(:ignored_versions) { ["..."] }
    end

    context "when on a pre-release" do
      let(:dependency_version) { "1.2.0-pre1" }

      it "updates to newer pre-releases" do
        expect(latest_resolvable_version).
          to eq(Dependabot::Utils::Go::Version.new("1.2.0-pre2"))
      end
    end

    it "doesn't update regular releases to newer pre-releases" do
      expect(latest_resolvable_version).to_not eq("1.2.0-pre2")
    end

    context "for libraries" do
      let(:requirements) { [] }

      it "updates the version" do
        expect(latest_resolvable_version).
          to eq(Dependabot::Utils::Go::Version.new("1.1.0"))
      end
    end

    it "updates v2+ modules"
    it "doesn't update to v2+ modules with un-versioned paths"
    it "updates modules that don't live at a repository root"
    it "updates Git SHAs to releases that include them"
    it "doesn't updates Git SHAs to releases that don't include them"

    context "for Git pseudo-versions" do
      let(:dependency_version) { "1.2.0-pre2.0.20181018214848-1f3e41dce654" }

      pending "updates to newer commits to master" do
        expect(latest_resolvable_version.to_s).
          to eq("1.2.0-pre2.0.20181018214848-bbed29f74d16")
      end
    end

    it "doesn't update Git SHAs not on master to newer commits to master"
    # TODO: sub-dependencies?
  end
end
