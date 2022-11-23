# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/go_modules/native_helpers"
require "dependabot/go_modules/update_checker/latest_version_finder"

RSpec.describe Dependabot::GoModules::UpdateChecker::LatestVersionFinder do
  let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-lib" }

  let(:dependency_version) { "1.0.0" }

  let(:security_advisories) { [] }

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

  let(:raise_on_ignored) { false }

  let(:goprivate) { "*" }

  let(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: [],
      ignored_versions: ignored_versions,
      security_advisories: security_advisories,
      raise_on_ignored: raise_on_ignored,
      goprivate: goprivate
    )
  end

  describe "#latest_version" do
    context "when there's a newer major version but not a new minor version" do
      it "returns the latest minor version for the dependency's current major version" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.1.0"))
      end

      context "with an unrestricted goprivate" do
        let(:goprivate) { "" }

        it "returns the latest minor version for the dependency's current major version" do
          expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.1.0"))
        end
      end

      context "with an org specific goprivate" do
        let(:goprivate) { "github.com/dependabot-fixtures/*" }

        it "returns the latest minor version for the dependency's current major version" do
          expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.1.0"))
        end
      end
    end

    context "when already on the latest version" do
      let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-lib/v3" }
      let(:dependency_version) { "3.0.0" }

      it "returns the current version" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("3.0.0"))
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
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.0.6"))
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
      it "returns the newest non-prerelease" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.1.0"))
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

    context "when the package url doesn't include any valid meta tags" do
      let(:dependency_files) { [go_mod] }
      let(:dependency_name) { "example.com/web/dependabot.com" }
      let(:dependency_version) { "1.7.0" }
      let(:go_mod) do
        Dependabot::DependencyFile.new(
          name: "go.mod",
          content: fixture("projects", "missing_meta_tag", "go.mod")
        )
      end

      it "raises a DependencyFileNotResolvable error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { finder.latest_version }.
          to raise_error(error_class) do |error|
          expect(error.message).to include("example.com/web/dependabot.com")
        end
      end
    end

    context "when the package url is internal/invalid" do
      let(:dependency_files) { [go_mod] }
      let(:dependency_name) { "pkg-errors" }
      let(:dependency_version) { "1.0.0" }
      let(:go_mod) do
        Dependabot::DependencyFile.new(
          name: "go.mod",
          content: fixture("projects", "unrecognized_import", "go.mod")
        )
      end

      it "raises a DependencyFileNotResolvable error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { finder.latest_version }.
          to raise_error(error_class) do |error|
          expect(error.message).to include("pkg-errors")
        end
      end
    end

    context "when the dependency's major version is invalid because it's not specified in its go.mod" do
      let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-lib/v2" }
      let(:dependency_version) { "2.0.0" }

      it "raises a DependencyFileNotResolvable error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { finder.latest_version }.
          to raise_error(error_class) do |error|
          expect(error.message).to include("github.com/dependabot-fixtures/go-modules-lib/v2")
          expect(error.message).to include("version \"v2.0.0\" invalid")
        end
      end
    end

    context "when the dependency's major version is invalid because not properly imported" do
      let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-lib" }
      let(:dependency_version) { "3.0.0" }

      it "raises a DependencyFileNotResolvable error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { finder.latest_version }.
          to raise_error(error_class) do |error|
          expect(error.message).to include("github.com/dependabot-fixtures/go-modules-lib")
          expect(error.message).to include("version \"v3.0.0\" invalid")
        end
      end
    end

    context "when the module is unreachable" do
      let(:dependency_files) { [go_mod] }
      let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-private" }
      let(:dependency_version) { "1.0.0" }
      let(:go_mod) do
        Dependabot::DependencyFile.new(
          name: "go.mod",
          content: fixture("projects", "unreachable_dependency", "go.mod")
        )
      end

      it "raises a GitDependenciesNotReachable error" do
        error_class = Dependabot::GitDependenciesNotReachable
        expect { finder.latest_version }.
          to raise_error(error_class) do |error|
          expect(error.message).to include("github.com/dependabot-fixtures/go-modules-private")
          expect(error.dependency_urls).
            to eq(["github.com/dependabot-fixtures/go-modules-private"])
        end
      end

      context "with an unrestricted goprivate" do
        let(:goprivate) { "" }

        it "raises a GitDependenciesNotReachable error" do
          error_class = Dependabot::GitDependenciesNotReachable
          expect { finder.latest_version }.
            to raise_error(error_class) do |error|
            expect(error.message).to include("github.com/dependabot-fixtures/go-modules-private")
            expect(error.dependency_urls).
              to eq(["github.com/dependabot-fixtures/go-modules-private"])
          end
        end
      end

      context "with an org specific goprivate" do
        let(:goprivate) { "github.com/dependabot-fixtures/*" }

        it "raises a GitDependenciesNotReachable error" do
          error_class = Dependabot::GitDependenciesNotReachable
          expect { finder.latest_version }.
            to raise_error(error_class) do |error|
            expect(error.message).to include("github.com/dependabot-fixtures/go-modules-private")
            expect(error.dependency_urls).
              to eq(["github.com/dependabot-fixtures/go-modules-private"])
          end
        end
      end
    end

    context "with a retracted update version" do
      # latest release v1.0.1 is retracted
      let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-retracted" }

      it "doesn't return the retracted version" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.0.0"))
      end
    end

    context "when the latest version is an '+incompatible' version" do # https://golang.org/ref/mod#incompatible-versions
      let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-incompatible" }
      let(:dependency_version) { "2.0.0+incompatible" }

      it "returns the current version" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("2.0.0+incompatible"))
      end
    end

    context "when raise_on_ignored is true" do
      let(:raise_on_ignored) { true }

      context "when a later version is allowed" do
        let(:dependency_version) { "1.0.0" }
        let(:ignored_versions) { ["= 1.0.1"] }

        it "doesn't raise an error" do
          expect { finder.latest_version }.not_to raise_error
        end
      end

      context "when already on the latest version" do
        let(:dependency_version) { "1.1.0" }
        let(:ignored_versions) { ["> 1.1.0"] }

        it "doesn't raise an error" do
          expect { finder.latest_version }.not_to raise_error
        end
      end

      context "when all later versions are ignored" do
        let(:dependency_version) { "1.0.1" }
        let(:ignored_versions) { ["> 1.0.1"] }

        it "raises AllVersionsIgnored" do
          expect { finder.latest_version }.
            to raise_error(Dependabot::AllVersionsIgnored)
        end
      end
    end
  end

  describe "#lowest_security_fix_version" do
    subject { finder.lowest_security_fix_version }

    let(:current_version) { "1.0.0" }

    context "when on a stable release and a newer versions are available" do
      it "returns the lowest available new release" do
        expect(finder.lowest_security_fix_version).to eq(Dependabot::GoModules::Version.new("1.0.1"))
      end
    end

    context "with Dependabot-ignored versions" do
      let(:ignored_versions) { ["= 1.0.1"] }

      it "doesn't return Dependabot-ignored versions" do
        expect(finder.lowest_security_fix_version).to eq(Dependabot::GoModules::Version.new("1.0.5"))
      end
    end

    # Ask Nish: why don't all these pass in a security advisory?  Is the idea that below is testing
    # using a security advisory? vs above is testing specific behavior of the function regardless
    # of the security advisory?... Do we expect this method to be called even when no security advisory?
    context "with a go.mod vulnerable version" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "go_modules",
            vulnerable_versions: ["<= 1.0.5"]
          )
        ]
      end

      it "doesn't return to the vulnerable version" do
        expect(finder.lowest_security_fix_version).to eq(Dependabot::GoModules::Version.new("1.0.6"))
      end

      # TODO: add test for what it returns when no non-vulnerable version available... or ignored?
    end

    context "when on a pre-release" do
      let(:dependency_version) { "1.2.0-pre1" }

      it "returns newest pre-release" do
        expect(finder.lowest_security_fix_version).to eq(Dependabot::GoModules::Version.new("1.2.0-pre2"))
      end
    end

    context "when on a stable release and a newer prerelease is available" do
      let(:current_version) { "1.1.0" }

      it "doesn't return pre-release" do
        expect(finder.lowest_security_fix_version).to_not eq(Dependabot::GoModules::Version.new("1.2.0-pre2"))
      end
    end
  end
end
