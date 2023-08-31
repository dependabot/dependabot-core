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

  let(:credentials) { github_credentials }
  let(:requirements_to_unlock) { :own }
  let(:dependency_files) { project_dependency_files(project_name) }

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
      let(:project_name) { "invalid_version_constraint" }

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        expect { resolver.latest_resolvable_version }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a library using a >= PHP constraint" do
      let(:project_name) { "php_specified_in_library" }
      let(:dependency_name) { "phpdocumentor/reflection-docblock" }
      let(:dependency_version) { "2.0.4" }
      let(:string_req) { "2.0.4" }

      it { is_expected.to eq(Dependabot::Composer::Version.new("3.3.2")) }
    end

    context "with an application using a >= PHP constraint" do
      let(:project_name) { "php_specified_without_lockfile" }
      let(:dependency_name) { "phpdocumentor/reflection-docblock" }
      let(:dependency_version) { "2.0.4" }
      let(:string_req) { "2.0.4" }

      it { is_expected.to eq(Dependabot::Composer::Version.new("3.3.2")) }

      context "the minimum version of which is invalid" do
        let(:dependency_version) { "4.2.0" }
        let(:string_req) { "4.2.0" }

        it { is_expected.to be >= Dependabot::Composer::Version.new("4.3.1") }
      end
    end

    context "with an application using a ^ PHP constraint" do
      context "the minimum version of which is invalid" do
        let(:project_name) { "php_specified_min_invalid_without_lockfile" }
        let(:dependency_name) { "phpdocumentor/reflection-docblock" }
        let(:dependency_version) { "2.0.4" }
        let(:string_req) { "2.0.4" }

        it { is_expected.to eq(Dependabot::Composer::Version.new("3.2.2")) }
      end
    end

    context "updating a subdependency that's not required anymore" do
      let(:project_name) { "subdependency_no_longer_required" }
      let(:requirements) { [] }
      let(:latest_allowable_version) { Gem::Version.new("6.0.0") }
      let(:dependency_name) { "doctrine/dbal" }
      let(:dependency_version) { "2.1.5" }

      it { is_expected.to be_nil }
    end

    context "with a dependency that's provided by another dep" do
      let(:project_name) { "provided_dependency" }
      let(:string_req) { "^1.0" }
      let(:latest_allowable_version) { Gem::Version.new("6.0.0") }
      let(:dependency_name) { "php-http/client-implementation" }
      let(:dependency_version) { nil }

      it { is_expected.to eq(Dependabot::Composer::Version.new("1.0")) }
    end

    context "with a dependency that uses a stability flag" do
      let(:project_name) { "stability_flag" }
      let(:string_req) { "@stable" }
      let(:latest_allowable_version) { Gem::Version.new("1.25.1") }
      let(:dependency_name) { "monolog/monolog" }
      let(:dependency_version) { "1.0.2" }
      let(:requirements_to_unlock) { :none }

      it { is_expected.to eq(Dependabot::Composer::Version.new("1.25.1")) }
    end

    context "with a library that requires itself" do
      let(:project_name) { "requires_self" }

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        expect { resolver.latest_resolvable_version }.
          to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include("cannot require itself")
          end
      end
    end

    context "with a library that uses a dev branch" do
      let(:project_name) { "dev_branch" }
      let(:dependency_name) { "monolog/monolog" }
      let(:latest_allowable_version) { Gem::Version.new("1.25.1") }
      let(:string_req) { "dev-1.x" }
      let(:dependency_version) { nil }

      it { is_expected.to eq(Dependabot::Composer::Version.new("1.25.1")) }
    end

    context "with a local VCS source" do
      let(:project_name) { "local_vcs_source" }

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        expect { resolver.latest_resolvable_version }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a private registry that 404s" do
      let(:project_name) { "private_registry_not_found" }
      let(:dependency_name) { "dependabot/dummy-pkg-a" }
      let(:dependency_version) { nil }
      let(:string_req) { "*" }
      let(:latest_allowable_version) { Gem::Version.new("6.0.0") }

      it "raises a Dependabot::PrivateSourceTimedOut error" do
        expect { resolver.latest_resolvable_version }.
          to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to start_with(
              'The "https://github.com/dependabot/composer-not-found/packages.json"' \
              " file could not be downloaded"
            )
          end
      end
    end

    context "with a forced oom error" do
      let(:project_name) { "php_specified_in_library" }
      let(:dependency_name) { "phpdocumentor/reflection-docblock" }
      let(:dependency_version) { "2.0.4" }
      let(:string_req) { "2.0.4" }

      before { ENV["DEPENDABOT_TEST_MEMORY_ALLOCATION"] = "16G" }
      after { ENV.delete("DEPENDABOT_TEST_MEMORY_ALLOCATION") }

      it "raises a Dependabot::OutOfMemory error" do
        expect { resolver.latest_resolvable_version }.
          to raise_error(Dependabot::OutOfMemory)
      end
    end

    context "with a name that is only valid in v1" do
      let(:project_name) { "v1/invalid_v2_name" }
      let(:dependency_name) { "monolog/monolog" }
      let(:latest_allowable_version) { Gem::Version.new("1.25.1") }
      let(:dependency_version) { "1.0.2" }

      it { is_expected.to eq(Dependabot::Composer::Version.new("1.25.1")) }
    end

    context "with a dependency name that is only valid in v1" do
      let(:project_name) { "v1/invalid_v2_requirement" }
      let(:dependency_name) { "monolog/Monolog" }
      let(:latest_allowable_version) { Gem::Version.new("1.25.1") }
      let(:dependency_version) { "1.0.2" }

      it { is_expected.to eq(Dependabot::Composer::Version.new("1.25.1")) }
    end

    context "with an unresolvable path VCS source" do
      let(:project_name) { "unreachable_path_vcs_source" }

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        expect { resolver.latest_resolvable_version }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a platform extension that cannot be added" do
      let(:project_name) { "unaddable_platform_req" }
      let(:dependency_name) { "monolog/monolog" }
      let(:latest_allowable_version) { Gem::Version.new("1.25.1") }
      let(:dependency_version) { "1.0.2" }

      it { is_expected.to eq(Dependabot::Composer::Version.new("1.25.1")) }
    end

    context "with an invalid version string" do
      let(:project_name) { "invalid_version_string" }

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        expect { resolver.latest_resolvable_version }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a missing vcs repository source (composer v1)" do
      let(:project_name) { "v1/vcs_source_unreachable" }

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        expect { resolver.latest_resolvable_version }.
          to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
            expect(error.dependency_urls).
              to eq(["https://github.com/dependabot-fixtures/this-repo-does-not-exist.git"])
          end
      end
    end

    context "with a missing vcs repository source" do
      let(:project_name) { "vcs_source_unreachable" }

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        expect { resolver.latest_resolvable_version }.
          to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
            expect(error.dependency_urls).
              to eq(["https://github.com/dependabot-fixtures/this-repo-does-not-exist.git"])
          end
      end
    end

    context "with a missing git repository source" do
      let(:project_name) { "git_source_unreachable" }
      let(:dependency_name) { "symfony/polyfill-mbstring" }
      let(:dependency_version) { "1.0.1" }
      let(:requirements) do
        [{
          file: "composer.json",
          requirement: "1.0.*",
          groups: [],
          source: nil
        }]
      end

      it "raises a Dependabot::GitDependenciesNotReachable error" do
        expect { resolver.latest_resolvable_version }.
          to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
            expect(error.dependency_urls).
              to eq(["https://github.com/no-exist-sorry/monolog.git"])
          end
      end
    end

    context "with an unreachable private registry" do
      let(:project_name) { "unreachable_private_registry" }
      let(:dependency_name) { "dependabot/dummy-pkg-a" }
      let(:dependency_version) { nil }
      let(:string_req) { "*" }
      let(:latest_allowable_version) { Gem::Version.new("6.0.0") }

      before { ENV["COMPOSER_PROCESS_TIMEOUT"] = "1" }
      after { ENV.delete("COMPOSER_PROCESS_TIMEOUT") }

      it "raises a Dependabot::PrivateSourceTimedOut error" do
        pending("TODO: this URL has no DNS record post GitHub acquisition, so switch to a routable URL that hangs")
        expect { resolver.latest_resolvable_version }.
          to raise_error(Dependabot::PrivateSourceTimedOut) do |error|
            expect(error.source).to eq("https://composer.dependabot.com")
          end
      end
    end
  end
end
