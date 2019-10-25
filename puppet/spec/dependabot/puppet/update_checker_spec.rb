# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/puppet/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Puppet::UpdateChecker do
  it_behaves_like "an update checker"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "puppet"
    )
  end
  let(:dependency_name) { "puppetlabs-dsc" }
  let(:dependency_version) { "1.4.0" }
  let(:dependency_requirements) do
    [{
      file: "Puppetfile",
      requirement: "1.4.0",
      source: nil,
      groups: []
    }]
  end
  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "Puppetfile",
        content: puppet_file_content
      )
    ]
  end
  let(:puppet_file_content) { %(mod "puppetlabs/dsc", '1.4.0') }
  let(:ignored_versions) { [] }
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions
    )
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  describe "#latest_version" do
    subject(:latest_version) { checker.latest_version }

    let(:puppet_forge_url) do
      "https://forgeapi.puppet.com/v3/modules/puppetlabs-dsc"\
      "?exclude_fields=readme,license,changelog,reference"
    end

    before do
      stub_request(:get, puppet_forge_url).
        to_return(status: 200, body: puppet_forge_response)
    end
    let(:puppet_forge_response) do
      fixture("forge_responses", puppet_forge_fixture_name)
    end
    let(:puppet_forge_fixture_name) { "puppetlabs-dsc.json" }

    it { is_expected.to eq(Dependabot::Puppet::Version.new("1.9.2")) }

    it "proxies to LatestVersionFinder#latest_version class" do
      dummy_latest_version_finder =
        instance_double(
          described_class::LatestVersionFinder,
          latest_version: "latest"
        )

      expect(described_class::LatestVersionFinder).
        to receive(:new).
        with(
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: ignored_versions,
          security_advisories: []
        ).and_return(dummy_latest_version_finder)

      expect(checker.latest_version).to eq("latest")
    end

    context "with a git dependency" do
      let(:dependency_name) { "utf8-ranges" }
      let(:dependency_version) { "83141b376b93484341c68fbca3ca110ae5cd2708" }
      let(:dependency_requirements) do
        [{
          file: "Puppetfile",
          requirement: nil,
          groups: [],
          source: {
            type: "git",
            url: "https://github.com/BurntSushi/utf8-ranges",
            branch: nil,
            ref: nil
          }
        }]
      end

      before do
        git_url = "https://github.com/BurntSushi/utf8-ranges.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
          with(basic_auth: %w(x-access-token token)).
          to_return(
            status: 200,
            body: fixture("git", "upload_packs", "utf8-ranges"),
            headers: git_header
          )
      end

      it { is_expected.to eq("47afd3c09c6583afdf4083fc9644f6f64172c8f8") }

      context "with a version-like tag" do
        let(:dependency_version) { "d5094c7e9456f2965dec20de671094a98c6929c2" }
        let(:dependency_requirements) do
          [{
            file: "Puppetfile",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/BurntSushi/utf8-ranges",
              branch: nil,
              ref: "0.1.3"
            }
          }]
        end

        # The SHA of the next version tag
        it { is_expected.to eq("83141b376b93484341c68fbca3ca110ae5cd2708") }
      end

      context "with a non-version tag" do
        let(:dependency_version) { "gitsha" }
        let(:dependency_requirements) do
          [{
            file: "Puppetfile",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/BurntSushi/utf8-ranges",
              branch: nil,
              ref: "something"
            }
          }]
        end

        it { is_expected.to eq(dependency_version) }
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    it "just proxies to the #latest_version method" do
      allow(checker).to receive(:latest_version).and_return("latest")
      expect(checker.latest_resolvable_version).to eq("latest")
    end
  end

  describe "#updated_requirements" do
    subject(:updated_requirements) { checker.updated_requirements }

    it "updates the requirement to the latest version" do
      allow(checker).to receive(:latest_version).
        and_return(Dependabot::Puppet::Version.new("1.9.2"))

      expect(checker.updated_requirements).
        to eq(
          [{
            file: "Puppetfile",
            requirement: "1.9.2",
            source: nil,
            groups: []
          }]
        )
    end

    context "with a git dependency" do
      let(:dependency_name) { "utf8-ranges" }
      let(:dependency_version) { "83141b376b93484341c68fbca3ca110ae5cd2708" }
      let(:dependency_requirements) do
        [{
          file: "Puppetfile",
          requirement: nil,
          groups: [],
          source: {
            type: "git",
            url: "https://github.com/BurntSushi/utf8-ranges",
            branch: nil,
            ref: nil
          }
        }]
      end

      before do
        git_url = "https://github.com/BurntSushi/utf8-ranges.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
          with(basic_auth: %w(x-access-token token)).
          to_return(
            status: 200,
            body: fixture("git", "upload_packs", "utf8-ranges"),
            headers: git_header
          )
      end

      context "with a version-like tag" do
        let(:dependency_version) { "d5094c7e9456f2965dec20de671094a98c6929c2" }
        let(:dependency_requirements) do
          [{
            file: "Puppetfile",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/BurntSushi/utf8-ranges",
              branch: nil,
              ref: "0.1.3"
            }
          }]
        end

        it "updates the requirement to the latest tag" do
          expect(checker.updated_requirements).
            to eq(
              [{
                file: "Puppetfile",
                requirement: nil,
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/BurntSushi/utf8-ranges",
                  branch: nil,
                  ref: "1.0.0"
                }
              }]
            )
        end
      end
    end
  end
end
