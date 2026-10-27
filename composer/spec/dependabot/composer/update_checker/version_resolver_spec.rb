# typed: false
# frozen_string_literal: true

# Sorbet cannot resolve the child-only project_name fixture or class-scope generated examples.

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
        expect { resolver.latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    # version constraint: >= 2.0.4, == 3.3.2 (debugging logs)
    context "when version constraint is set as requirement" do
      let(:project_name) { "php_specified_in_library" }
      let(:dependency_name) { "phpdocumentor/reflection-docblock" }
      let(:latest_allowable_version) { Gem::Version.new("3.3.2") }
      let(:dependency_version) { "2.0.4" }
      let(:string_req) { "2.0.4" }

      it { is_expected.to eq(Dependabot::Composer::Version.new("3.3.2")) }
    end

    # combined constraint: >= 2.0.4, == 3.0.0 (debugging logs)
    # But latest allowable version is 3.0.0
    context "when version constraint is set as requirement, but pushing to the latest_allowable_version 3.0.0 now" do
      let(:project_name) { "php_specified_in_library" }
      let(:dependency_name) { "phpdocumentor/reflection-docblock" }
      let(:latest_allowable_version) { Gem::Version.new("3.0.0") }
      let(:dependency_version) { "2.0.4" }
      let(:string_req) { "2.0.4" }

      it { is_expected.to eq(Dependabot::Composer::Version.new("3.0.0")) }
    end

    # combined constraint: >= 1.0.1, == 1.1.0 (debugging logs)
    context "when version constraint is set as dev-requirement" do
      let(:project_name) { "php_specified_in_library" }
      let(:dependency_name) { "monolog/monolog" }
      let(:latest_allowable_version) { Gem::Version.new("1.1.0") }
      let(:dependency_version) { "1.0.1" }
      let(:string_req) { "1.0.1" }

      it { is_expected.to eq(Dependabot::Composer::Version.new("1.1.0")) }
    end

    # combined constraint: >= 2.0.4 (debugging logs)
    context "when latest_allowable_version is not set" do
      let(:project_name) { "php_specified_in_library" }
      let(:dependency_name) { "phpdocumentor/reflection-docblock" }
      let(:latest_allowable_version) { nil }
      let(:dependency_version) { "2.0.4" }
      let(:string_req) { "2.0.4" }

      it { is_expected.to eq(Dependabot::Composer::Version.new("3.3.2")) }
    end

    # combined constraint: ==3.0.0 (debugging logs) not set to the latest in the registry.
    context "when version constraint is not set (in existing composer.json)" do
      let(:project_name) { "php_specified_in_library" }
      let(:dependency_name) { "phpdocumentor/reflection-docblock" }
      let(:latest_allowable_version) { Gem::Version.new("3.0.0") }
      let(:dependency_version) { nil }
      let(:string_req) { nil }

      it { is_expected.to eq(Dependabot::Composer::Version.new("3.0.0")) }
    end

    # combined constraint: >= 0
    context "when both version constraint and latest_allowable_version are not set" do
      let(:project_name) { "php_specified_in_library" }
      let(:dependency_name) { "phpdocumentor/reflection-docblock" }
      let(:latest_allowable_version) { nil }
      let(:dependency_version) { nil }
      let(:string_req) { nil }

      it { is_expected.to eq(Dependabot::Composer::Version.new("3.3.2")) }
    end

    context "with an application using a >= PHP constraint" do
      let(:project_name) { "php_specified_without_lockfile" }
      let(:dependency_name) { "phpdocumentor/reflection-docblock" }
      let(:dependency_version) { "2.0.4" }
      let(:string_req) { "2.0.4" }
      let(:latest_allowable_version) { Gem::Version.new("3.3.2") }

      it { is_expected.to eq(Dependabot::Composer::Version.new("3.3.2")) }

      context "when the minimum version is invalid, 3.3.2 is less than 4.2.0" do
        let(:dependency_version) { "4.2.0" }
        let(:string_req) { "4.2.0" }

        it { is_expected.to be_nil }
      end
    end

    context "with an application using a ^ PHP constraint" do
      context "when the minimum version is invalid" do
        let(:project_name) { "php_specified_min_invalid_without_lockfile" }
        let(:dependency_name) { "phpdocumentor/reflection-docblock" }
        let(:dependency_version) { "2.0.4" }
        let(:string_req) { "2.0.4" }
        let(:latest_allowable_version) { Gem::Version.new("3.2.2") }

        it { is_expected.to eq(Dependabot::Composer::Version.new("3.2.2")) }

        %w(require requires).each do |wording|
          context "when Composer reports an implicit PHP requirement using #{wording}" do
            it "retries with a PHP version satisfying the dependency requirement" do
              expect(Dependabot::SharedHelpers).to receive(:run_helper_subprocess).ordered do
                manifest = JSON.parse(File.read("composer.json"))
                expect(manifest.dig("config", "platform", "php")).to eq("5.2.0")

                raise Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                  message: "phpdocumentor/reflection-docblock 3.2.2 #{wording} php ^5.3.0 -> " \
                           "your php version (5.2.0) does not satisfy that requirement.",
                  error_context: {}
                )
              end
              expect(Dependabot::SharedHelpers).to receive(:run_helper_subprocess).ordered do
                manifest = JSON.parse(File.read("composer.json"))
                expect(manifest.dig("config", "platform", "php")).to eq("5.3.0")
                "3.2.2"
              end

              expect(resolver.latest_resolvable_version).to eq(Dependabot::Composer::Version.new("3.2.2"))
            end
          end
        end
      end
    end

    context "when updating a subdependency that's not required anymore" do
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

      it { is_expected.to be_nil }
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
        expect { resolver.latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
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
        expect { resolver.latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a private registry that 404s" do
      let(:project_name) { "private_registry_not_found" }
      let(:dependency_name) { "dependabot/dummy-pkg-a" }
      let(:dependency_version) { nil }
      let(:string_req) { "*" }
      let(:latest_allowable_version) { Gem::Version.new("6.0.0") }

      it "raises a Dependabot::PrivateSourceTimedOut error" do
        expect { resolver.latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include(
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

      before { ENV["DEPENDABOT_TEST_MEMORY_ALLOCATION"] = "32G" }
      after { ENV.delete("DEPENDABOT_TEST_MEMORY_ALLOCATION") }

      it "raises a Dependabot::OutOfMemory error" do
        expect { resolver.latest_resolvable_version }
          .to raise_error(Dependabot::OutOfMemory)
      end
    end

    context "when PHP can't allocate memory from the OS" do
      let(:project_name) { "php_specified_in_library" }
      let(:dependency_name) { "phpdocumentor/reflection-docblock" }
      let(:dependency_version) { "2.0.4" }
      let(:string_req) { "2.0.4" }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess).and_raise(
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "mmap() failed: [12] Cannot allocate memory\n\n" \
                     "mmap() failed: [12] Cannot allocate memory\nOut of memory",
            error_context: {}
          )
        )
      end

      it "raises a Dependabot::OutOfMemory error" do
        expect { resolver.latest_resolvable_version }
          .to raise_error(Dependabot::OutOfMemory)
      end
    end

    context "with a platform extension that cannot be added" do
      let(:project_name) { "unaddable_platform_req" }
      let(:dependency_name) { "monolog/monolog" }
      let(:latest_allowable_version) { Gem::Version.new("1.25.1") }
      let(:dependency_version) { "1.0.2" }

      it { is_expected.to eq(Dependabot::Composer::Version.new("1.25.1")) }
    end

    context "with an explicitly configured platform extension" do
      let(:dependency_name) { "mongodb/mongodb" }
      let(:dependency_version) { "2.4.2" }
      let(:string_req) { "^2.4.2" }
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "composer.json",
            content: JSON.pretty_generate(
              "require" => {
                "php" => ">=8.1",
                "ext-mongodb" => "^2.4",
                "mongodb/mongodb" => "^2.4.2",
                "vendor/needs-ext" => "^1.0"
              },
              "config" => { "platform" => { "ext-mongodb" => "2.4.0" } }
            )
          ),
          Dependabot::DependencyFile.new(
            name: "composer.lock",
            content: {
              "packages" => [],
              "packages-dev" => [],
              "platform-overrides" => { "ext-mongodb" => "2.4.0" }
            }.to_json
          )
        ]
      end
      let(:written_manifests) { [] }
      let(:responses) { [] }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess) do
          written_manifests << JSON.parse(File.read("composer.json"))
          response = responses.shift
          raise response if response.is_a?(Exception)

          response
        end
      end

      def missing_platform_error(problem)
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Your requirements could not be resolved to an installable set of packages.\n\n" \
                   "  Problem 1\n    - #{problem}",
          error_context: {}
        )
      end

      context "when a newer version requires an incompatible extension version" do
        let(:responses) do
          [missing_platform_error(
            "mongodb/mongodb 2.5.0 requires ext-mongodb ^2.5 -> it has the wrong version installed (2.4.0)."
          )]
        end

        it "treats the explicit platform version as a hard constraint" do
          expect(resolver.latest_resolvable_version).to be_nil
          expect(written_manifests.length).to eq(1)
          expect(written_manifests.map { |json| json.dig("config", "platform", "ext-mongodb") })
            .to all(eq("2.4.0"))
        end
      end

      context "when a root requirement conflicts with the explicit platform version" do
        let(:responses) do
          [missing_platform_error(
            "PHP extension ext-mongodb ^2.5 but it has the wrong version installed (2.4.0)"
          )]
        end

        it "raises a DependencyFileNotResolvable error with the Composer diagnostic" do
          expect { resolver.latest_resolvable_version }
            .to raise_error(Dependabot::DependencyFileNotResolvable, /PHP extension ext-mongodb/)
          expect(written_manifests.length).to eq(1)
        end
      end

      context "when an undeclared extension is missing" do
        let(:responses) do
          [
            missing_platform_error("vendor/needs-ext 1.0.0 requires ext-foo ^1.2 -> it is missing from your system."),
            "2.4.2"
          ]
        end

        it "synthesizes the missing extension without touching the explicit one" do
          expect(resolver.latest_resolvable_version).to eq(Dependabot::Composer::Version.new("2.4.2"))
          expect(written_manifests.length).to eq(2)
          expect(written_manifests.last.dig("config", "platform"))
            .to eq("ext-mongodb" => "2.4.0", "ext-foo" => "1.2", "php" => "8.1")
        end
      end
    end

    context "with an invalid version string" do
      let(:project_name) { "invalid_version_string" }

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        expect { resolver.latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a missing vcs repository source" do
      let(:project_name) { "vcs_source_unreachable" }

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        expect { resolver.latest_resolvable_version }
          .to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
            expect(error.dependency_urls)
              .to eq(["https://github.com/dependabot-fixtures/this-repo-does-not-exist.git"])
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
        expect { resolver.latest_resolvable_version }
          .to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
            expect(error.dependency_urls)
              .to eq(["https://github.com/no-exist-sorry/monolog.git"])
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
        expect { resolver.latest_resolvable_version }
          .to raise_error(Dependabot::PrivateSourceTimedOut) do |error|
            expect(error.source).to eq("https://example.com:81")
          end
      end
    end

    context "when PHP runs out of memory while checking the original requirements" do
      let(:project_name) { "php_specified_without_lockfile" }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess).and_invoke(
          lambda { |**|
            raise Dependabot::SharedHelpers::HelperSubprocessFailed.new(
              message: "Your requirements could not be resolved to an installable set of packages.",
              error_context: {}
            )
          },
          lambda { |**|
            raise Dependabot::SharedHelpers::HelperSubprocessFailed.new(
              message: "mmap() failed: [12] Cannot allocate memory\nOut of memory",
              error_context: {}
            )
          }
        )
      end

      it "raises a Dependabot::OutOfMemory error" do
        expect { resolver.latest_resolvable_version }
          .to raise_error(Dependabot::OutOfMemory)
        expect(Dependabot::SharedHelpers).to have_received(:run_helper_subprocess).twice
      end
    end

    context "when run_update_checker returns nil" do
      let(:project_name) { "check_original_requirements_resolvable" }

      before do
        # Mock run_update_checker to return nil
        allow(resolver).to receive(:run_update_checker).and_return(nil) # rubocop:disable RSpec/SubjectStub
      end

      it "returns false when run_update_checker returns nil" do
        result = resolver.send(:check_original_requirements_resolvable)
        expect(result).to be(false)
      end
    end

    context "when encountering a dist-only internal package" do
      let(:project_name) { "path_source_with_dev_prefix" }
      let(:dependency_name) { "path_dep/path_dep" }
      let(:dependency_version) { "dev-main" }
      let(:latest_allowable_version) { nil }
      let(:requirements_to_unlock) { :none }
      let(:string_req) { "dev-main" }

      it "resolves the latest version without a version mismatch" do
        expect(resolver.latest_resolvable_version).to be_nil
      end
    end
  end
end
