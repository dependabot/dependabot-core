# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nuget/file_parser"
require "dependabot/nuget/update_checker"
require "dependabot/nuget/requirement"
require "dependabot/nuget/version"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Nuget::UpdateChecker do
  it_behaves_like "an update checker"

  let(:repo_contents_path) { write_tmp_repo(dependency_files) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  let(:checker) do
    # We have to run the FileParser first to ensure the discovery.json is generated.
    Dependabot::Nuget::FileParser.new(dependency_files: dependency_files,
                                      source: source,
                                      repo_contents_path: repo_contents_path).parse
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "nuget"
    )
  end
  let(:dependency_requirements) do
    [{ file: "my.csproj", requirement: "1.1.1", groups: ["dependencies"], source: nil }]
  end
  let(:dependency_name) { "Microsoft.Extensions.DependencyModel" }
  let(:dependency_version) { "1.1.1" }

  let(:dependency_files) { [csproj] }
  let(:csproj) do
    Dependabot::DependencyFile.new(name: "my.csproj", content: csproj_body)
  end
  let(:csproj_body) { fixture("csproj", "basic.csproj") }

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }

  let(:version_class) { Dependabot::Nuget::Version }

  describe "up_to_date?" do
    subject(:up_to_date?) { checker.up_to_date? }

    context "with a property dependency" do
      context "whose property couldn't be found" do
        let(:dependency_name) { "Nuke.Common" }
        let(:dependency_requirements) do
          [{
            requirement: "$(NukeVersion)",
            file: "my.csproj",
            groups: ["dependencies"],
            source: nil,
            metadata: { property_name: "NukeVersion" }
          }]
        end
        let(:dependency_version) { "$(NukeVersion)" }

        it { is_expected.to eq(true) }
      end
    end

    context "with a transient dependency" do
      context "with no vulnerability" do
        let(:dependency_name) { "Nuke.Common" }
        let(:dependency_requirements) { [] }
        let(:dependency_version) { "2.0.0" }

        it { is_expected.to eq(true) }
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }
    it { is_expected.to be_nil }
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject { checker.latest_resolvable_version_with_no_unlock }
    it { is_expected.to be_nil }
  end

  describe "#requirements_unlocked_or_can_be?" do
    let(:csproj_body) do
      fixture("csproj", "property_version.csproj")
    end

    subject(:requirements_unlocked_or_can_be) do
      checker.requirements_unlocked_or_can_be?
    end

    context "with a property dependency" do
      let(:dependency_requirements) do
        [{
          requirement: "0.1.434",
          file: "my.csproj",
          groups: ["dependencies"],
          source: nil,
          metadata: { property_name: "NukeVersion" }
        }]
      end
      let(:dependency_name) { "Nuke.Common" }
      let(:dependency_version) { "0.1.434" }

      it { is_expected.to eq(true) }
    end
  end

  describe "#lowest_security_fix_version" do
    subject { checker.lowest_security_fix_version }

    let(:target_version) { "2.0.0" }
    let(:vulnerable_versions) { ["< 2.0.0"] }
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "nuget",
          vulnerable_versions: vulnerable_versions
        )
      ]
    end

    it { is_expected.to eq(target_version) }

    context "the security vulnerability excludes all compatible packages" do
      let(:target_version) { "1.1.1" }
      let(:vulnerable_versions) { ["< 999.999.999"] } # it's all bad

      it "reports the currently installed version" do
        is_expected.to eq(target_version)
      end
    end
  end

  describe "#updated_dependencies(requirements_to_unlock: :all)" do
    subject(:updated_dependencies) do
      checker.updated_dependencies(requirements_to_unlock: :all)
    end

    context "with a property dependency" do
      let(:dependency_requirements) do
        [{
          requirement: "0.1.434",
          file: "my.csproj",
          groups: ["dependencies"],
          source: nil,
          metadata: { property_name: "NukeVersion" }
        }]
      end
      let(:dependency_name) { "Nuke.Common" }
      let(:dependency_version) { "0.1.434" }

      context "that is used for multiple dependencies" do
        let(:csproj_body) do
          fixture("csproj", "property_version.csproj")
        end

        context "where all dependencies can update to the latest version" do
          it "delegates to PropertyUpdater" do
            is_expected.to eq([
              Dependabot::Dependency.new(
                name: "Nuke.CodeGeneration",
                version: "6.3.0",
                previous_version: dependency_version,
                requirements: dependency_requirements,
                previous_requirements: dependency_requirements,
                package_manager: "nuget"
              ),
              Dependabot::Dependency.new(
                name: "Nuke.Common",
                version: "6.3.0",
                previous_version: dependency_version,
                requirements: dependency_requirements,
                previous_requirements: dependency_requirements,
                package_manager: "nuget"
              )
            ])
          end
        end
      end
    end
  end
end
