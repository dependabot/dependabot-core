# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/composer/update_checker/version_resolver"

RSpec.describe Dependabot::Composer::UpdateChecker::VersionResolver do
  subject(:resolver) do
    described_class.new(
      credentials: credentials,
      dependency: dependency,
      dependency_files: dependency_files,
      latest_allowable_version: latest_allowable_version,
      requirements_to_unlock: requirements_to_unlock
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
  let(:requirements_to_unlock) { :own }
  let(:dependency_files) { [manifest, lockfile] }
  let(:manifest) do
    Dependabot::DependencyFile.new(
      name: "composer.json",
      content: fixture("composer_files", manifest_fixture_name)
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "composer.lock",
      content: fixture("lockfiles", lockfile_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "invalid_version_constraint" }
  let(:lockfile_fixture_name) { "invalid_version_constraint" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "composer"
    )
  end
  let(:requirements) do
    [{
      file: "composer.json",
      requirement: string_req,
      groups: [],
      source: nil
    }]
  end
  let(:latest_allowable_version) { Gem::Version.new("6.0.0") }
  let(:dependency_name) { "symfony/translation" }
  let(:dependency_version) { "4.0.7" }
  let(:string_req) { "^4.0" }

  describe "latest_resolvable_version" do
    subject { resolver.latest_resolvable_version }

    context "with an invalid version constraint" do
      let(:manifest_fixture_name) { "invalid_version_constraint" }
      let(:lockfile_fixture_name) { "invalid_version_constraint" }

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        expect { resolver.latest_resolvable_version }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "updating a subdependency that's not required anymore" do
      let(:manifest_fixture_name) { "exact_version" }
      let(:lockfile_fixture_name) { "version_conflict_at_latest" }
      let(:requirements) { [] }
      let(:latest_allowable_version) { Gem::Version.new("6.0.0") }
      let(:dependency_name) { "doctrine/dbal" }
      let(:dependency_version) { "2.1.5" }

      it { is_expected.to be_nil }
    end

    context "with a dependecy that's provided by another dep" do
      let(:manifest_fixture_name) { "provided_dependency" }
      let(:dependency_files) { [manifest] }
      let(:string_req) { "^1.0" }
      let(:latest_allowable_version) { Gem::Version.new("6.0.0") }
      let(:dependency_name) { "php-http/client-implementation" }
      let(:dependency_version) { nil }

      it { is_expected.to eq(Dependabot::Composer::Version.new("1.0")) }
    end

    context "with a library that requires itself" do
      let(:dependency_files) { [manifest] }
      let(:manifest_fixture_name) { "requires_self" }

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        expect { resolver.latest_resolvable_version }.
          to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include("cannot require itself")
          end
      end
    end

    context "with a local VCS source" do
      let(:manifest_fixture_name) { "local_vcs_source" }
      let(:dependency_files) { [manifest] }

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        expect { resolver.latest_resolvable_version }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a private registry that 404s" do
      let(:manifest_fixture_name) { "private_registry_not_found" }
      let(:dependency_files) { [manifest] }
      let(:dependency_name) { "dependabot/dummy-pkg-a" }
      let(:dependency_version) { nil }
      let(:string_req) { "*" }
      let(:latest_allowable_version) { Gem::Version.new("6.0.0") }

      it "raises a Dependabot::PrivateSourceTimedOut error" do
        expect { resolver.latest_resolvable_version }.
          to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to eq(
              'The "https://dependabot.com/composer-not-found/packages.json"'\
              " file could not be downloaded (HTTP/1.1 404 Not Found)"
            )
          end
      end
    end

    # This test is extremely slow, as it neds to wait for Composer to time out.
    # As a result we currently keep it commented out.
    # context "with an unreachable private registry" do
    #   let(:manifest_fixture_name) { "unreachable_private_registry" }
    #   let(:dependency_files) { [manifest] }
    #   let(:dependency_name) { "dependabot/dummy-pkg-a" }
    #   let(:dependency_version) { nil }
    #   let(:string_req) { "*" }
    #   let(:latest_allowable_version) { Gem::Version.new("6.0.0") }

    #   it "raises a Dependabot::PrivateSourceTimedOut error" do
    #     expect { resolver.latest_resolvable_version }.
    #       to raise_error(Dependabot::PrivateSourceTimedOut) do |error|
    #         expect(error.source).to eq("https://composer.dependabot.com")
    #       end
    #   end
    # end
  end
end
