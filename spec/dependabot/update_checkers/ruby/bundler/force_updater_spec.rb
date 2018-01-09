# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/ruby/bundler/force_updater"
require "bundler/compact_index_client"

RSpec.describe Dependabot::UpdateCheckers::Ruby::Bundler::ForceUpdater do
  let(:updater) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      target_version: target_version,
      credentials: [
        {
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      ]
    )
  end
  let(:dependency_files) { [gemfile, lockfile] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: current_version,
      requirements: requirements,
      package_manager: "bundler"
    )
  end
  let(:dependency_name) { "onfido" }
  let(:current_version) { "0.7.1" }
  let(:target_version) { "0.8.2" }
  let(:requirements) do
    [{ file: "Gemfile", requirement: "~> 0.7.1", groups: [], source: nil }]
  end

  let(:gemfile) do
    Dependabot::DependencyFile.new(content: gemfile_body, name: "Gemfile")
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(content: lockfile_body, name: "Gemfile.lock")
  end

  before do
    allow_any_instance_of(Bundler::CompactIndexClient::Updater).
      to receive(:etag_for).and_return("")
    stub_request(:get, "https://index.rubygems.org/versions").
      to_return(status: 200, body: fixture("ruby", "rubygems-index"))
  end

  describe "#updated_dependencies" do
    subject(:updated_dependencies) { updater.updated_dependencies }

    context "when updating the dependency that requires the other" do
      before do
        info_url = "https://index.rubygems.org/info/"
        stub_request(:get, info_url + "diff-lcs").
          to_return(
            status: 200,
            body: fixture("ruby", "rubygems-info-diff-lcs")
          )
        stub_request(:get, info_url + "rspec-mocks").
          to_return(
            status: 200,
            body: fixture("ruby", "rubygems-info-rspec-mocks")
          )
        stub_request(:get, info_url + "rspec-support").
          to_return(
            status: 200,
            body: fixture("ruby", "rubygems-info-rspec-support")
          )
      end
      let(:gemfile_body) { fixture("ruby", "gemfiles", "version_conflict") }
      let(:lockfile_body) do
        fixture("ruby", "lockfiles", "version_conflict.lock")
      end
      let(:target_version) { "3.6.0" }
      let(:dependency_name) { "rspec-mocks" }
      let(:requirements) do
        [
          {
            file: "Gemfile",
            requirement: "= 3.5.0",
            groups: [:default],
            source: nil
          }
        ]
      end
      let(:expected_requirements) do
        [
          {
            file: "Gemfile",
            requirement: "3.6.0",
            groups: [:default],
            source: nil
          }
        ]
      end

      it "returns the right array of updated dependencies" do
        expect(updated_dependencies).to eq(
          [
            Dependabot::Dependency.new(
              name: "rspec-mocks",
              version: "3.6.0",
              previous_version: "3.5.0",
              requirements: expected_requirements,
              previous_requirements: requirements,
              package_manager: "bundler"
            ),
            Dependabot::Dependency.new(
              name: "rspec-support",
              version: "3.6.0",
              previous_version: "3.5.0",
              requirements: expected_requirements,
              previous_requirements: requirements,
              package_manager: "bundler"
            )
          ]
        )
      end
    end

    context "when updating the dependency that is required by the other" do
      before do
        info_url = "https://index.rubygems.org/info/"
        stub_request(:get, info_url + "diff-lcs").
          to_return(
            status: 200,
            body: fixture("ruby", "rubygems-info-diff-lcs")
          )
        stub_request(:get, info_url + "rspec-mocks").
          to_return(
            status: 200,
            body: fixture("ruby", "rubygems-info-rspec-mocks")
          )
        stub_request(:get, info_url + "rspec-support").
          to_return(
            status: 200,
            body: fixture("ruby", "rubygems-info-rspec-support")
          )
      end

      let(:gemfile_body) { fixture("ruby", "gemfiles", "version_conflict") }
      let(:lockfile_body) do
        fixture("ruby", "lockfiles", "version_conflict.lock")
      end
      let(:target_version) { "3.6.0" }
      let(:dependency_name) { "rspec-support" }
      let(:requirements) do
        [
          {
            file: "Gemfile",
            requirement: "= 3.5.0",
            groups: [:default],
            source: nil
          }
        ]
      end
      let(:expected_requirements) do
        [
          {
            file: "Gemfile",
            requirement: "3.6.0",
            groups: [:default],
            source: nil
          }
        ]
      end

      it "returns the right array of updated dependencies" do
        expect(updated_dependencies).to eq(
          [
            Dependabot::Dependency.new(
              name: "rspec-support",
              version: "3.6.0",
              previous_version: "3.5.0",
              requirements: expected_requirements,
              previous_requirements: requirements,
              package_manager: "bundler"
            ),
            Dependabot::Dependency.new(
              name: "rspec-mocks",
              version: "3.6.0",
              previous_version: "3.5.0",
              requirements: expected_requirements,
              previous_requirements: requirements,
              package_manager: "bundler"
            )
          ]
        )
      end
    end

    context "when two dependencies require the same subdependency" do
      before do
        info_url = "https://index.rubygems.org/info/"
        stub_request(:get, info_url + "diff-lcs").
          to_return(
            status: 200,
            body: fixture("ruby", "rubygems-info-diff-lcs")
          )
        stub_request(:get, info_url + "rspec-mocks").
          to_return(
            status: 200,
            body: fixture("ruby", "rubygems-info-rspec-mocks")
          )
        stub_request(:get, info_url + "rspec-expectations").
          to_return(
            status: 200,
            body: fixture("ruby", "rubygems-info-rspec-expectations")
          )
        stub_request(:get, info_url + "rspec-support").
          to_return(
            status: 200,
            body: fixture("ruby", "rubygems-info-rspec-support")
          )
      end

      let(:gemfile_body) do
        fixture("ruby", "gemfiles", "version_conflict_mutual_sub")
      end
      let(:lockfile_body) do
        fixture("ruby", "lockfiles", "version_conflict_mutual_sub.lock")
      end

      let(:dependency_name) { "rspec-mocks" }
      let(:target_version) { "3.6.0" }
      let(:requirements) do
        [
          {
            file: "Gemfile",
            requirement: "~> 3.5.0",
            groups: [:default],
            source: nil
          }
        ]
      end
      let(:expected_requirements) do
        [
          {
            file: "Gemfile",
            requirement: "~> 3.6.0",
            groups: [:default],
            source: nil
          }
        ]
      end

      it "returns the right array of updated dependencies" do
        expect(updated_dependencies).to eq(
          [
            Dependabot::Dependency.new(
              name: "rspec-mocks",
              version: "3.6.0",
              previous_version: "3.5.0",
              requirements: expected_requirements,
              previous_requirements: requirements,
              package_manager: "bundler"
            ),
            Dependabot::Dependency.new(
              name: "rspec-expectations",
              version: "3.6.0",
              previous_version: "3.5.0",
              requirements: expected_requirements,
              previous_requirements: requirements,
              package_manager: "bundler"
            )
          ]
        )
      end
    end

    context "when another dependency would need to be downgraded" do
      before do
        stub_request(:get, "https://index.rubygems.org/info/i18n").
          to_return(status: 200, body: fixture("ruby", "rubygems-info-i18n"))
        stub_request(:get, "https://index.rubygems.org/info/ibandit").
          to_return(status: 200, body: fixture("ruby", "rubygems-info-ibandit"))
      end

      let(:gemfile_body) do
        fixture("ruby", "gemfiles", "version_conflict_requires_downgrade")
      end
      let(:lockfile_body) do
        fixture("ruby", "lockfiles", "version_conflict_requires_downgrade.lock")
      end
      let(:target_version) { "0.8.6" }
      let(:dependency_name) { "i18n" }

      it "raises a resolvability error" do
        expect { updater.updated_dependencies }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "when the ruby version would need to change" do
      before do
        stub_request(:get, "https://index.rubygems.org/info/public_suffix").
          to_return(
            status: 200,
            body: fixture("ruby", "rubygems-info-public_suffix")
          )
      end

      let(:gemfile_body) do
        fixture("ruby", "gemfiles", "legacy_ruby")
      end
      let(:lockfile_body) do
        fixture("ruby", "lockfiles", "legacy_ruby.lock")
      end
      let(:target_version) { "2.0.5" }
      let(:dependency_name) { "public_suffix" }

      it "raises a resolvability error" do
        expect { updater.updated_dependencies }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end
  end
end
