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
        to eq(Dependabot::GoModules::Version.new("1.1.0"))
    end

    it "doesn't update major semver versions" do
      expect(latest_resolvable_version).
        to_not eq(Dependabot::GoModules::Version.new("2.0.0"))
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
          to eq(Dependabot::GoModules::Version.new("1.0.1"))
      end
    end

    it "doesn't update to (Dependabot) ignored versions" do
      # TODO: let(:ignored_versions) { ["..."] }
    end

    context "when on a pre-release" do
      let(:dependency_version) { "1.2.0-pre1" }

      it "updates to newer pre-releases" do
        expect(latest_resolvable_version).
          to eq(Dependabot::GoModules::Version.new("1.2.0-pre2"))
      end
    end

    it "doesn't update regular releases to newer pre-releases" do
      expect(latest_resolvable_version).to_not eq(
        Dependabot::GoModules::Version.new("1.2.0-pre2")
      )
    end

    context "doesn't update indirect dependencies (not supported)" do
      let(:requirements) { [] }
      it do
        is_expected.to eq(
          Dependabot::GoModules::Version.new(dependency.version)
        )
      end
    end

    it "updates v2+ modules"
    it "doesn't update to v2+ modules with un-versioned paths"
    it "updates modules that don't live at a repository root"
    it "updates Git SHAs to releases that include them"
    it "doesn't updates Git SHAs to releases that don't include them"

    context "for Git pseudo-versions" do
      context "with releases available" do
        let(:dependency_version) { "1.0.0-20181018214848-ab544413d0d3" }

        it "doesn't update them, currently" do
          expect(latest_resolvable_version.to_s).to eq(dependency_version)
        end
      end

      context "with newer revisions available" do
        let(:dependency_version) { "1.2.0-pre2.0.20181018214848-1f3e41dce654" }

        pending "updates to newer commits to master" do
          expect(latest_resolvable_version.to_s).
            to eq("1.2.0-pre2.0.20181018214848-bbed29f74d16")
        end
      end
    end

    it "doesn't update Git SHAs not on master to newer commits to master"

    context "when the package url returns 404" do
      let(:dependency_files) { [go_mod] }
      let(:project_name) { "missing_package" }
      let(:repo_contents_path) { build_tmp_repo(project_name) }

      let(:dependency_name) { "example.com/test/package" }
      let(:dependency_version) { "1.7.0" }

      let(:go_mod) do
        Dependabot::DependencyFile.new(name: "go.mod", content: go_mod_body)
      end
      let(:go_mod_body) { fixture("projects", project_name, "go.mod") }

      it "raises a DependencyFileNotResolvable error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { latest_resolvable_version }.
          to raise_error(error_class) do |error|
          expect(error.message).to include("example.com/test/package")
        end
      end
    end

    context "when the package url doesn't include any valid meta tags" do
      let(:dependency_files) { [go_mod] }
      let(:project_name) { "missing_meta_tag" }
      let(:repo_contents_path) { build_tmp_repo(project_name) }

      let(:dependency_name) { "web.archive.org/web/dependabot.com" }
      let(:dependency_version) { "1.7.0" }

      let(:go_mod) do
        Dependabot::DependencyFile.new(name: "go.mod", content: go_mod_body)
      end
      let(:go_mod_body) { fixture("projects", project_name, "go.mod") }

      it "raises a DependencyFileNotResolvable error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { latest_resolvable_version }.
          to raise_error(error_class) do |error|
          expect(error.message).to include("web.archive.org/web/dependabot.com")
        end
      end
    end
  end
end
