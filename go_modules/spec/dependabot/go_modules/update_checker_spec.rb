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
      ignored_versions: ignored_versions,
      raise_on_ignored: raised_on_ignored
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
  let(:raised_on_ignored) { false }
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

    context "with Dependabot ignored versions" do
      let(:ignored_versions) { ["> 1.0.1"] }

      it "doesn't update to (Dependabot) ignored versions" do
        expect(latest_resolvable_version).
          to eq(Dependabot::GoModules::Version.new("1.0.1"))
      end
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

      let(:dependency_name) { "example.com/web/dependabot.com" }
      let(:dependency_version) { "1.7.0" }

      let(:go_mod) do
        Dependabot::DependencyFile.new(name: "go.mod", content: go_mod_body)
      end
      let(:go_mod_body) { fixture("projects", project_name, "go.mod") }

      it "raises a DependencyFileNotResolvable error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { latest_resolvable_version }.
          to raise_error(error_class) do |error|
          expect(error.message).to include("example.com/web/dependabot.com")
        end
      end
    end

    context "with a retracted update version" do
      # latest release v1.0.1 is retracted
      let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-retracted" }

      pending "doesn't update to the retracted version" do
        expect(latest_resolvable_version).
          to eq(Dependabot::GoModules::Version.new("1.0.0"))
      end
    end

    context "when the package url is internal/invalid" do
      let(:dependency_files) { [go_mod] }
      let(:project_name) { "unrecognized_import" }
      let(:repo_contents_path) { build_tmp_repo(project_name) }

      let(:dependency_name) { "pkg-errors" }
      let(:dependency_version) { "1.0.0" }

      let(:go_mod) do
        Dependabot::DependencyFile.new(name: "go.mod", content: go_mod_body)
      end
      let(:go_mod_body) { fixture("projects", project_name, "go.mod") }

      it "raises a DependencyFileNotResolvable error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { latest_resolvable_version }.
          to raise_error(error_class) do |error|
          expect(error.message).to include("pkg-errors")
        end
      end
    end

    context "when already on the latest version for the major" do
      let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-lib/v2" }
      let(:dependency_version) { "2.0.0" }

      it "returns the current version" do
        expect(latest_resolvable_version).
          to eq(Dependabot::GoModules::Version.new("2.0.0"))
      end
    end

    context "when raised_on_ignored is true" do
      let(:raised_on_ignored) { true }

      context "when a later version is allowed" do
        let(:dependency_version) { "1.0.0" }
        let(:ignored_versions) { ["= 1.0.1"] }

        it "doesn't raise an error" do
          expect { latest_resolvable_version }.not_to raise_error
        end
      end

      context "when already on the latest version" do
        let(:dependency_version) { "1.1.0" }
        let(:ignored_versions) { ["> 1.1.0"] }

        it "doesn't raise an error" do
          expect { latest_resolvable_version }.not_to raise_error
        end
      end

      context "when all later versions are ignored" do
        let(:dependency_version) { "1.0.1" }
        let(:ignored_versions) { ["> 1.0.1"] }

        it "raises AllVersionsIgnored" do
          expect { latest_resolvable_version }.
            to raise_error(Dependabot::AllVersionsIgnored)
        end
      end
    end
  end
end
