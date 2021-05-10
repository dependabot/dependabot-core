# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/go_modules/native_helpers"
require "dependabot/go_modules/update_checker/latest_version_finder"

RSpec.describe Dependabot::GoModules::UpdateChecker::LatestVersionFinder do
  describe "#latest_version" do
    let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-lib" }

    let(:dependency_version) { "1.0.0" }

    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: dependency_version,
        package_manager: "go_modules",
        requirements: [{
          file: "go.mod",
          requirement: dependency_version,
          groups: [],
          source: { type: "default", source: dependency_name }
        }]
      )
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

    let(:ignored_versions) { [] }

    let(:finder) do
      described_class.new(
        dependency: dependency,
        dependency_files: dependency_files,
        credentials: [{
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }],
        ignored_versions: ignored_versions
      )
    end

    context "when there's a newer major version but not a new minor version" do
      it "returns the latest minor version for the dependency's current major version" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.1.0"))
      end
    end

    context "when already on the latest version" do
      let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-lib/v2" }
      let(:dependency_version) { "2.0.0" }

      it "returns the current version" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("2.0.0"))
      end
    end

    context "with a go.mod excluded version" do
      let(:go_mod_content) do
        <<~GOMOD
          module foobar
          require #{dependency_name} v#{dependency_version}
          exclude #{dependency_name} v1.1.0
        GOMOD
      end

      it "doesn't return to the excluded version" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.0.1"))
      end
    end

    context "with Dependabot-ignored versions" do
      let(:ignored_versions) { ["> 1.0.1"] }

      it "doesn't return Dependabot-ignored versions" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.0.1"))
      end
    end

    context "when on a pre-release" do
      let(:dependency_version) { "1.2.0-pre1" }

      it "returns newest pre-release" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.2.0-pre2"))
      end
    end

    context "when on a stable release and a newer prerelease is available" do
      it "doesn't return pre-release" do
        expect(finder.latest_version).to_not eq(Dependabot::GoModules::Version.new("1.2.0-pre2"))
      end
    end

    context "for a Git pseudo-version with releases available" do
      let(:dependency_version) { "1.0.0-20181018214848-ab544413d0d3" }

      it "doesn't return the releases, currently" do
        expect(finder.latest_version).to eq(dependency_version)
      end
    end

    context "for a Git pseudo-version with newer revisions available" do
      let(:dependency_version) { "1.2.0-pre2.0.20181018214848-1f3e41dce654" }

      pending "updates to newer commits to master" do
        expect(finder.latest_version).to eq("1.2.0-pre2.0.20181018214848-bbed29f74d16")
      end
    end

    context "when the package url returns 404" do
      let(:dependency_files) { [go_mod] }
      let(:dependency_name) { "example.com/test/package" }
      let(:dependency_version) { "1.7.0" }
      let(:go_mod) do
        Dependabot::DependencyFile.new(
          name: "go.mod",
          content: fixture("projects", "missing_package", "go.mod")
        )
      end

      it "raises a DependencyFileNotResolvable error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { finder.latest_version }.
          to raise_error(error_class) do |error|
          expect(error.message).to include("example.com/test/package")
        end
      end
    end

    context "when the latest version is an '+incompatible' version" do # https://golang.org/ref/mod#incompatible-versions
      let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-incompatible" }
      let(:dependency_version) { "2.0.0+incompatible" }

      it "returns the current version" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("2.0.0+incompatible"))
      end
    end
  end
end
