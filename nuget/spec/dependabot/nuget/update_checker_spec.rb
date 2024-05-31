# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nuget/update_checker"
require "dependabot/nuget/version"
require_common_spec "update_checkers/shared_examples_for_update_checkers"
RSpec.describe Dependabot::Nuget::UpdateChecker do
  it_behaves_like "an update checker"

  let(:checker) do
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

  def nuspec_url(name, version)
    "https://api.nuget.org/v3-flatcontainer/#{name.downcase}/#{version}/#{name.downcase}.nuspec"
  end

  def registration_index_url(name)
    "https://api.nuget.org/v3/registration5-gz-semver2/#{name.downcase}/index.json"
  end

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

        it { is_expected.to be(true) }
      end
    end

    context "with a transient dependency" do
      context "with no vulnerability" do
        let(:dependency_name) { "Nuke.Common" }
        let(:dependency_requirements) { [] }
        let(:dependency_version) { "2.0.0" }

        it { is_expected.to be(true) }
      end
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    it "delegates to the VersionFinder class" do
      version_finder_class = described_class::VersionFinder
      dummy_version_finder = instance_double(version_finder_class)
      allow(version_finder_class)
        .to receive(:new)
        .and_return(dummy_version_finder)
      allow(dummy_version_finder)
        .to receive(:latest_version_details)
        .and_return(version: Dependabot::Nuget::Version.new("1.2.3"))

      expect(checker.latest_version).to eq("1.2.3")
    end

    context "the package could not be found on any source" do
      before do
        stub_request(:get, registration_index_url("microsoft.extensions.dependencymodel"))
          .to_return(status: 404)
      end

      it "reports the current version" do
        expect(checker.latest_version).to eq("1.1.1")
      end
    end
  end

  describe "#lowest_security_fix_version" do
    subject { checker.lowest_security_fix_version }

    it "delegates to the VersionFinder class" do
      version_finder_class = described_class::VersionFinder
      dummy_version_finder = instance_double(version_finder_class)
      allow(version_finder_class)
        .to receive(:new)
        .and_return(dummy_version_finder)
      allow(dummy_version_finder)
        .to receive(:lowest_security_fix_version_details)
        .and_return(version: Dependabot::Nuget::Version.new("1.2.3"))

      expect(checker.lowest_security_fix_version).to eq("1.2.3")
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

  describe "#can_update?(requirements_to_unlock: :all)" do
    subject(:can_update) { checker.can_update?(requirements_to_unlock: :all) }

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
          before do
            allow(checker).to receive(:all_property_based_dependencies).and_return(
              [
                Dependabot::Dependency.new(
                  name: "Nuke.Common",
                  version: "0.1.434",
                  requirements: dependency_requirements,
                  package_manager: "nuget"
                ),
                Dependabot::Dependency.new(
                  name: "Nuke.CodeGeneration",
                  version: "0.1.434",
                  requirements: dependency_requirements,
                  package_manager: "nuget"
                )
              ]
            )

            property_updater_class = described_class::PropertyUpdater
            dummy_property_updater = instance_double(property_updater_class)
            allow(checker).to receive(:latest_version).and_return("0.9.0")
            allow(checker).to receive(:property_updater).and_return(dummy_property_updater)
            allow(dummy_property_updater).to receive(:update_possible?).and_return(true)
          end

          it { is_expected.to be(true) }
        end

        context "where not all dependencies can update to the latest version" do
          before do
            allow(checker).to receive(:all_property_based_dependencies).and_return(
              [
                Dependabot::Dependency.new(
                  name: "Nuke.Common",
                  version: "0.1.434",
                  requirements: dependency_requirements,
                  package_manager: "nuget"
                ),
                Dependabot::Dependency.new(
                  name: "Nuke.CodeGeneration",
                  version: "0.1.434",
                  requirements: dependency_requirements,
                  package_manager: "nuget"
                )
              ]
            )

            property_updater_class = described_class::PropertyUpdater
            dummy_property_updater = instance_double(property_updater_class)
            allow(checker).to receive(:latest_version).and_return("0.9.0")
            allow(checker).to receive(:property_updater).and_return(dummy_property_updater)
            allow(dummy_property_updater).to receive(:update_possible?).and_return(false)
          end

          it { is_expected.to be(false) }
        end
      end
    end
  end

  describe "#updated_requirements" do
    subject(:updated_requirements) { checker.updated_requirements }

    let(:target_version) { "2.1.0" }

    it "delegates to the RequirementsUpdater" do
      allow(checker).to receive(:latest_version_details).and_return(
        {
          version: target_version,
          source_url: nil,
          nuspec_url: nuspec_url(dependency_name, target_version),
          repo_url: "https://api.nuget.org/v3/index.json"
        }
      )
      expect(described_class::RequirementsUpdater).to receive(:new).with(
        requirements: dependency_requirements,
        latest_version: target_version,
        source_details: {
          source_url: nil,
          nuspec_url: nuspec_url(dependency_name, target_version),
          repo_url: "https://api.nuget.org/v3/index.json"
        }
      ).and_call_original
      expect(updated_requirements).to eq(
        [{
          file: "my.csproj",
          requirement: target_version,
          groups: ["dependencies"],
          source: {
            type: "nuget_repo",
            url: "https://api.nuget.org/v3/index.json",
            source_url: nil,
            nuspec_url: nuspec_url(dependency_name, target_version)
          }
        }]
      )
    end

    context "with a security vulnerability" do
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

      it "delegates to the RequirementsUpdater" do
        allow(checker).to receive(:lowest_security_fix_version_details).and_return(
          {
            version: target_version,
            source_url: nil,
            nuspec_url: nuspec_url(dependency_name, target_version),
            repo_url: "https://api.nuget.org/v3/index.json"
          }
        )

        expect(described_class::RequirementsUpdater).to receive(:new).with(
          requirements: dependency_requirements,
          latest_version: target_version,
          source_details: {
            source_url: nil,
            nuspec_url: nuspec_url(dependency_name, target_version),
            repo_url: "https://api.nuget.org/v3/index.json"
          }
        ).and_call_original
        expect(updated_requirements).to eq(
          [{
            file: "my.csproj",
            requirement: target_version,
            groups: ["dependencies"],
            source: {
              type: "nuget_repo",
              url: "https://api.nuget.org/v3/index.json",
              source_url: nil,
              nuspec_url: nuspec_url(dependency_name, target_version)
            }
          }]
        )
      end

      context "the security vulnerability excludes all compatible packages" do
        subject(:updated_requirement_version) { updated_requirements[0].fetch(:requirement) }

        let(:target_version) { "1.1.1" }
        let(:vulnerable_versions) { ["< 999.999.999"] } # it's all bad

        before do
          # only vulnerable versions are returned
          stub_request(:get, registration_index_url(dependency_name))
            .to_return(
              status: 200,
              body: {
                items: [
                  items: [
                    {
                      catalogEntry: {
                        version: "1.1.1" # the currently installed version, but it's vulnerable
                      }
                    },
                    {
                      catalogEntry: {
                        version: "3.0.0" # newer version, but it's still vulnerable
                      }
                    }
                  ]
                ]
              }.to_json
            )
        end

        it "reports the currently installed version" do
          expect(updated_requirement_version).to eq(target_version)
        end
      end
    end
  end

  describe "#requirements_unlocked_or_can_be?" do
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

      it { is_expected.to be(true) }

      context "whose property couldn't be found" do
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

        it { is_expected.to be(false) }
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
          before do
            allow(checker).to receive(:latest_version).and_return("0.9.0")
            allow(checker).to receive(:all_property_based_dependencies).and_return(
              [
                Dependabot::Dependency.new(
                  name: "Nuke.Common",
                  version: "0.1.434",
                  requirements: dependency_requirements,
                  package_manager: "nuget"
                ),
                Dependabot::Dependency.new(
                  name: "Nuke.CodeGeneration",
                  version: "0.1.434",
                  requirements: dependency_requirements,
                  package_manager: "nuget"
                )
              ]
            )
          end

          it "delegates to PropertyUpdater" do
            property_updater_class = described_class::PropertyUpdater
            dummy_property_updater = instance_double(property_updater_class)
            allow(checker).to receive(:property_updater).and_return(dummy_property_updater)
            allow(dummy_property_updater).to receive(:update_possible?).and_return(true)
            expect(dummy_property_updater).to receive(:updated_dependencies).and_return([dependency])

            updated_dependencies
          end
        end
      end
    end
  end
end
