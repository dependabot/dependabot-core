# typed: false
# frozen_string_literal: true

require "spec_helper"

require "dependabot/composer/update_checker"
require "dependabot/dependency_file"
require "dependabot/dependency"
require "dependabot/requirements_update_strategy"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Composer::UpdateChecker do
  let(:packagist_response) do
    sanitized_name = dependency_name.downcase.gsub("/", "--")
    fixture("packagist_responses", "#{sanitized_name}.json")
  end
  let(:packagist_url) { "https://repo.packagist.org/p2/monolog/monolog.json" }
  let(:project_name) { "exact_version" }
  let(:files) { project_dependency_files(project_name) }
  let(:credentials) { github_credentials }
  let(:requirements) do
    [{ file: "composer.json", requirement: "1.0.*", groups: [], source: nil }]
  end
  let(:dependency_version) { "1.0.1" }
  let(:dependency_name) { "monolog/monolog" }
  let(:requirements_update_strategy) { nil }
  let(:security_advisories) { [] }
  let(:raise_on_ignored) { false }
  let(:ignored_versions) { [] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "composer"
    )
  end
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      security_advisories: security_advisories,
      requirements_update_strategy: requirements_update_strategy
    )
  end

  before do
    url = "https://repo.packagist.org/p2/#{dependency_name.downcase}.json"
    stub_request(:get, url).to_return(status: 200, body: packagist_response)
  end

  it_behaves_like "an update checker"

  describe "#latest_version" do
    subject(:latest_version) { checker.latest_version }

    before do
      allow(checker).to receive(:latest_resolvable_version)
        .and_return(Gem::Version.new("1.17.0"))
    end

    it { is_expected.to eq(Gem::Version.new("3.2.0")) }

    context "when the user is ignoring the latest version" do
      let(:ignored_versions) { [">= 3.2.0.a, < 3.3"] }

      it { is_expected.to eq(Gem::Version.new("3.1.0")) }
    end

    context "when the user is ignoring all versions" do
      let(:ignored_versions) { [">= 0"] }

      it "returns latest_resolvable_version" do
        expect(latest_version).to eq(Gem::Version.new("1.17.0"))
      end

      context "when raise_on_ignored is enabled" do
        let(:raise_on_ignored) { true }

        it "raises an error" do
          expect { latest_version }.to raise_error(Dependabot::AllVersionsIgnored)
        end
      end
    end

    context "when packagist returns an empty array" do
      let(:packagist_response) { '{"packages":[]}' }

      before do
        allow(checker).to receive(:latest_resolvable_version)
          .and_return(Gem::Version.new("1.17.0"))
      end

      it { is_expected.to eq(Gem::Version.new("1.17.0")) }
    end

    context "with a path source" do
      before do
        stub_request(:get, "https://repo.packagist.org/p2/path_dep/path_dep.json")
          .to_return(status: 404)
      end

      context "when it is not the dependency we're checking" do
        it { is_expected.to eq(Gem::Version.new("3.2.0")) }
      end

      context "when it is the dependency we're checking" do
        let(:dependency_name) { "path_dep/path_dep" }
        let(:dependency_version) { "1.0.1" }
        let(:requirements) do
          [{
            requirement: "1.0.*",
            file: "composer.json",
            groups: ["runtime"],
            source: { type: "path" }
          }]
        end

        it { is_expected.to be_nil }
      end
    end

    context "with a git dependency" do
      let(:project_name) { "git_source" }
      let(:upload_pack_fixture) { "monolog" }

      let(:dependency_version) { "5267b03b1e4861c4657ede17a88f13ef479db482" }
      let(:requirements) do
        [{
          requirement: "dev-example",
          file: "composer.json",
          groups: ["runtime"],
          source: {
            type: "git",
            url: "https://github.com/dependabot/monolog.git",
            branch: "example",
            ref: nil
          }
        }]
      end

      let(:service_pack_url) do
        "https://github.com/dependabot/monolog.git/info/refs" \
          "?service=git-upload-pack"
      end

      before do
        stub_request(:get, service_pack_url)
          .to_return(
            status: 200,
            body: fixture("git", "upload_packs", upload_pack_fixture),
            headers: {
              "content-type" => "application/x-git-upload-pack-advertisement"
            }
          )
      end

      it { is_expected.to eq("303b8a83c87d5c6d749926cf02620465a5dcd0f2") }
    end
  end

  describe "#lowest_security_fix_version" do
    subject(:lowest_security_fix_version) { checker.lowest_security_fix_version }

    before do
      allow(checker).to receive(:latest_resolvable_version)
        .and_return(Gem::Version.new("1.17.0"))
    end

    it "finds the lowest available non-vulnerable version" do
      expect(lowest_security_fix_version).to eq(Gem::Version.new("1.0.2"))
    end

    context "with a security vulnerability" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "composer",
            vulnerable_versions: ["<= 1.22.0"]
          )
        ]
      end

      it "finds the lowest available non-vulnerable version" do
        expect(lowest_security_fix_version).to eq(Gem::Version.new("1.22.1"))
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    before do
      allow(checker).to receive(:latest_version_from_registry)
        .and_return(Gem::Version.new("1.22.0"))
    end

    it "returns a non-normalized version, following semver" do
      expect(latest_resolvable_version.segments.count).to eq(3)
    end

    it { is_expected.to be >= Gem::Version.new("1.22.0") }

    context "when the user is ignoring the latest version" do
      let(:ignored_versions) { [">= 1.22.0.a, < 4.0"] }

      it { is_expected.to eq(Gem::Version.new("1.22.0")) }
    end

    context "without a lockfile" do
      it { is_expected.to be >= Gem::Version.new("1.22.0") }

      context "when there are conflicts at the version specified" do
        let(:project_name) { "conflicts" }
        let(:dependency_name) { "phpdocumentor/reflection-docblock" }
        let(:dependency_version) { nil }
        let(:requirements) do
          [{
            file: "composer.json",
            requirement: "^4.3",
            groups: [],
            source: nil
          }]
        end

        before do
          allow(checker).to receive(:latest_version_from_registry)
            .and_return(Gem::Version.new("4.3.0"))
        end

        it { is_expected.to be >= Gem::Version.new("4.3.0") }
      end

      context "when an old version of PHP is specified" do
        let(:project_name) { "old_php_specified" }
        let(:dependency_name) { "illuminate/support" }
        let(:dependency_version) { "5.2.7" }
        let(:requirements) do
          [{
            file: "composer.json",
            requirement: "^5.2.0",
            groups: ["runtime"],
            source: nil
          }]
        end

        before do
          allow(checker).to receive(:latest_version_from_registry)
            .and_return(Gem::Version.new("5.2.45"))
        end

        it { is_expected.to be >= Gem::Version.new("5.2.45") }

        context "when as a platform requirement" do
          let(:project_name) { "old_php_platform" }

          it { is_expected.to eq(Gem::Version.new("5.2.45")) }

          context "when an extension is specified that we don't have" do
            let(:project_name) { "missing_extension" }

            it "pretends the missing extension is there" do
              expect(latest_resolvable_version)
                .to eq(Dependabot::Composer::Version.new("5.2.45"))
            end
          end

          context "when the platform requirement only specifies an extension" do
            let(:project_name) { "bad_php" }

            it { is_expected.to eq(Gem::Version.new("5.2.45")) }
          end
        end
      end

      context "when an odd version of PHP is specified" do
        let(:project_name) { "odd_php_specified" }
        let(:dependency_name) { "illuminate/support" }
        let(:dependency_version) { "5.2.7" }
        let(:requirements) do
          [{
            file: "composer.json",
            requirement: "^5.2.0",
            groups: ["runtime"],
            source: nil
          }]
        end

        before do
          allow(checker).to receive(:latest_version_from_registry)
            .and_return(Gem::Version.new("5.2.45"))
        end

        it { is_expected.to be >= Gem::Version.new("5.2.45") }
      end
    end

    context "with a dev dependency" do
      let(:project_name) { "development_dependencies" }

      it { is_expected.to be >= Gem::Version.new("1.22.0") }
    end

    context "with a path source" do
      let(:project_name) { "path_source" }

      before do
        stub_request(:get, "https://repo.packagist.org/p2/path_dep/path_dep.json")
          .to_return(status: 404)
      end

      context "when it is not the dependency we're checking" do
        it { is_expected.to be >= Gem::Version.new("1.22.0") }
      end

      context "when it is the dependency we're checking" do
        let(:dependency_name) { "path_dep/path_dep" }
        let(:dependency_version) { "1.0.1" }
        let(:requirements) do
          [{
            requirement: "1.0.*",
            file: "composer.json",
            groups: ["runtime"],
            source: { type: "path" }
          }]
        end

        it { is_expected.to be_nil }
      end
    end

    context "with a private registry" do
      let(:project_name) { "private_registry" }
      let(:dependency_name) { "dependabot/dummy-pkg-a" }
      let(:dependency_version) { nil }
      let(:requirements) do
        [{
          file: "composer.json",
          requirement: "*",
          groups: [],
          source: nil
        }]
      end

      before do
        `composer clear-cache --quiet`
        url = "https://php.fury.io/dependabot-throwaway/packages.json"
        stub_request(:get, url)
          .to_return(status: 200, body: fixture("gemfury_response.json"))
      end

      context "with good credentials" do
        let(:gemfury_deploy_token) { ENV.fetch("GEMFURY_DEPLOY_TOKEN", nil) }
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "composer_repository",
            "registry" => "php.fury.io",
            "username" => gemfury_deploy_token,
            "password" => ""
          }]
        end

        it "returns the expected version" do
          skip("skipped because env var GEMFURY_DEPLOY_TOKEN is not set") if gemfury_deploy_token.nil?
          expect(latest_resolvable_version).to be >= Gem::Version.new("2.2.0")
        end
      end

      context "with bad credentials" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "composer_repository",
            "registry" => "php.fury.io",
            "username" => "bad",
            "password" => ""
          }]
        end

        it "raises a helpful error message" do
          expect { checker.latest_resolvable_version }
            .to raise_error do |error|
              expect(error)
                .to be_a(Dependabot::PrivateSourceAuthenticationFailure)
              expect(error.source).to eq("php.fury.io")
            end
        end
      end

      context "with no credentials" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }]
        end

        it "raises a helpful error message" do
          expect { checker.latest_resolvable_version }
            .to raise_error do |error|
              expect(error)
                .to be_a(Dependabot::PrivateSourceAuthenticationFailure)
              expect(error.source).to eq("php.fury.io")
            end
        end
      end
    end

    context "with a replaced dependency" do
      let(:project_name) { "replaced_dependency" }
      let(:dependency_name) { "illuminate/console" }
      let(:dependency_version) { nil }
      let(:requirements) do
        [{
          file: "composer.json",
          requirement: "5.5.*",
          groups: [],
          source: nil
        }]
      end

      it { is_expected.to be_nil }
    end

    context "with a version conflict at the latest version" do
      let(:project_name) { "version_conflict_at_latest" }
      let(:dependency_name) { "doctrine/dbal" }
      let(:dependency_version) { "2.1.5" }
      let(:requirements) do
        [{
          file: "composer.json",
          requirement: "1.0.*",
          groups: [],
          source: nil
        }]
      end
      let(:ignored_versions) { [">= 2.8.0"] }

      before do
        allow(checker).to receive(:latest_version_from_registry)
          .and_return(Gem::Version.new("2.1.7"))
      end

      it "is the highest resolvable version" do
        expect(latest_resolvable_version).to eq(Gem::Version.new("2.1.7"))
      end

      context "when the blocking dependency is a git dependency" do
        let(:project_name) { "git_source_conflict_at_latest" }

        it "is the highest resolvable version" do
          pending("composer currently ignores resolvability requirements for git dependencies.")
          expect(latest_resolvable_version).to eq(Gem::Version.new("2.1.7"))
        end
      end
    end

    context "with a version conflict in the current files" do
      let(:dependency_name) { "monolog/monolog" }
      let(:dependency_version) { "2.1.5" }
      let(:requirements) do
        [{
          file: "composer.json",
          requirement: "1.0.*",
          groups: [],
          source: nil
        }]
      end

      context "when there is no lockfile" do
        let(:project_name) { "version_conflict_without_lockfile" }

        it "raises a resolvability error" do
          expect { latest_resolvable_version }
            .to raise_error(Dependabot::DependencyFileNotResolvable)
        end
      end
    end

    context "with an update that can't resolve due to a version conflict" do
      let(:project_name) { "version_conflict_on_update" }
      let(:dependency_name) { "longman/telegram-bot" }
      let(:dependency_version) { "2.1.5" }
      let(:requirements) do
        [{
          file: "composer.json",
          requirement: "1.0.*",
          groups: [],
          source: nil
        }]
      end

      it { is_expected.to be_nil }

      it "logs an error" do
        allow(Dependabot.logger).to receive(:error)

        expect(latest_resolvable_version).to be_nil
        expect(Dependabot.logger).to have_received(:error).with(
          a_string_starting_with("Your requirements could not be resolved to an installable set of packages.")
        ).once

        expect(Dependabot.logger).to have_received(:error).with(
          a_string_starting_with("/home/dependabot/")
        ).at_least(:once)
      end

      context "when there is no lockfile" do
        let(:project_name) { "version_conflict_on_update_without_lockfile" }

        it { is_expected.to be_nil }

        context "when the conflict comes from a loose PHP version" do
          let(:project_name) { "version_conflict_library" }

          it { is_expected.to be_nil }
        end
      end
    end

    context "with a git source dependency" do
      let(:project_name) { "git_source" }

      let(:dependency_version) { "5267b03b1e4861c4657ede17a88f13ef479db482" }
      let(:requirements) do
        [{
          requirement: "dev-example",
          file: "composer.json",
          groups: ["runtime"],
          source: {
            type: "git",
            url: "https://github.com/dependabot/monolog.git",
            branch: "example"
          }
        }]
      end

      it { is_expected.to be_nil }
    end

    context "with a git source dependency that's not the dependency we're checking" do
      let(:project_name) { "git_source" }
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

      it { is_expected.to be >= Gem::Version.new("1.3.0") }
    end

    context "with a git source dependency that's not the dependency we're checking with an alias" do
      let(:project_name) { "git_source_alias" }
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

      it { is_expected.to be >= Gem::Version.new("1.3.0") }
    end

    context "with a git source dependency that's not the dependency we're checking with a stability flag" do
      let(:project_name) { "git_source_transitive" }
      let(:dependency_name) { "symfony/polyfill-mbstring" }
      let(:dependency_version) { "1.0.1" }
      let(:requirements) do
        [{
          requirement: "1.*@dev",
          file: "composer.json",
          groups: ["runtime"],
          source: {
            type: "git",
            url: "https://github.com/php-fig/log.git",
            branch: "master",
            ref: nil
          }
        }]
      end

      it { is_expected.to be_nil }
    end

    context "with a git source dependency that's not the dependency we're checking with a bad commit" do
      let(:project_name) { "git_source_bad_commit" }
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

      # Alternatively, this could raise an error. Either behaviour would be
      # fine - the below is just what we get with Composer at the moment
      # because we disabled downloading the files in
      # DependabotInstallationManager.
      it { is_expected.to be >= Gem::Version.new("1.3.0") }
    end

    context "with a git source dependency that's not the dependency we're checking with a git URL" do
      let(:project_name) { "git_source_git_url" }
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

      it { is_expected.to be >= Gem::Version.new("1.3.0") }
    end

    context "with a git source dependency that's not the dependency we're checking that is unreachable" do
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

      it "raises a helpful error" do
        expect { checker.latest_resolvable_version }
          .to raise_error do |error|
            expect(error).to be_a(Dependabot::GitDependenciesNotReachable)
            expect(error.dependency_urls)
              .to eq(["https://github.com/no-exist-sorry/monolog.git"])
          end
      end

      context "with a git URL" do
        let(:project_name) { "git_source_unreachable_git_url" }

        it "raises a helpful error" do
          expect { checker.latest_resolvable_version }
            .to raise_error do |error|
              expect(error).to be_a(Dependabot::GitDependenciesNotReachable)
              expect(error.dependency_urls)
                .to eq(["git@github.com:no-exist-sorry/monolog"])
            end
        end
      end
    end

    context "when an alternative source is specified" do
      let(:project_name) { "alternative_source" }
      let(:dependency_name) { "wpackagist-plugin/acf-to-rest-api" }
      let(:dependency_version) { "2.2.1" }
      let(:requirements) do
        [{
          file: "composer.json",
          requirement: "*",
          groups: ["runtime"],
          source: nil
        }]
      end

      before do
        allow(checker).to receive(:latest_version_from_registry)
          .and_return(Gem::Version.new("3.0.2"))
        stub_request(:get, "https://wpackagist.org/packages.json")
          .to_return(
            status: 200,
            body: fixture("wpackagist_response.json")
          )
      end

      it { is_expected.to be >= Gem::Version.new("3.0.2") }
    end

    context "when an autoload is specified" do
      let(:project_name) { "autoload" }
      let(:dependency_name) { "illuminate/support" }
      let(:dependency_version) { "5.2.7" }
      let(:requirements) do
        [{
          file: "composer.json",
          requirement: "^5.2.0",
          groups: ["runtime"],
          source: nil
        }]
      end

      it { is_expected.to be_nil }
    end

    context "with an invalid composer.json file" do
      let(:project_name) { "invalid_manifest" }

      it "raises a helpful error" do
        expect { latest_resolvable_version }.to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end
  end

  describe "#preferred_resolvable_version" do
    subject { checker.preferred_resolvable_version }

    let(:ignored_versions) { [">= 1.22.0.a, < 4.0"] }

    it { is_expected.to eq(Gem::Version.new("1.21.0")) }

    context "with an insecure version" do
      let(:dependency_version) { "1.0.1" }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "composer",
            vulnerable_versions: ["<= 1.15.0"]
          )
        ]
      end

      it { is_expected.to eq(Gem::Version.new("1.16.0")) }
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject(:latest_resolvable_version_with_no_unlock) do
      checker.latest_resolvable_version_with_no_unlock
    end

    context "with a git source dependency" do
      let(:project_name) { "git_source" }

      let(:dependency_version) { "5267b03b1e4861c4657ede17a88f13ef479db482" }
      let(:requirements) do
        [{
          requirement: "dev-example",
          file: "composer.json",
          groups: ["runtime"],
          source: {
            type: "git",
            url: "https://github.com/dependabot/monolog.git",
            branch: "example"
          }
        }]
      end

      it { is_expected.to be_nil }
    end
  end

  describe "#updated_requirements" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "monolog/monolog",
        version: "1.0.1",
        requirements: dependency_requirements,
        package_manager: "composer"
      )
    end
    let(:dependency_requirements) do
      [{
        file: "composer.json",
        requirement: "1.0.*",
        groups: [],
        source: nil
      }]
    end

    before do
      allow(checker)
        .to receive(:latest_resolvable_version)
        .and_return(Gem::Version.new("1.6.0"))
    end

    it "delegates to the RequirementsUpdater" do
      expect(described_class::RequirementsUpdater)
        .to receive(:new)
        .with(
          requirements: dependency_requirements,
          latest_resolvable_version: "1.6.0",
          update_strategy: Dependabot::RequirementsUpdateStrategy::BumpVersionsIfNecessary
        )
        .and_call_original
      expect(checker.updated_requirements)
        .to eq(
          [{
            file: "composer.json",
            requirement: "1.6.*",
            groups: [],
            source: nil
          }]
        )
    end

    context "with an insecure version" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "composer",
            vulnerable_versions: ["<= 1.15.0"]
          )
        ]
      end

      before do
        allow(checker)
          .to receive(:lowest_resolvable_security_fix_version)
          .and_return(Gem::Version.new("1.5.0"))
      end

      it "delegates to the RequirementsUpdater" do
        expect(described_class::RequirementsUpdater)
          .to receive(:new)
          .with(
            requirements: dependency_requirements,
            latest_resolvable_version: "1.5.0",
            update_strategy: Dependabot::RequirementsUpdateStrategy::BumpVersionsIfNecessary
          )
          .and_call_original
        expect(checker.updated_requirements)
          .to eq(
            [{
              file: "composer.json",
              requirement: "1.5.*",
              groups: [],
              source: nil
            }]
          )
      end
    end
  end

  describe "#requirements_unlocked_or_can_be?" do
    subject { checker.requirements_unlocked_or_can_be? }

    it { is_expected.to be(true) }

    context "with the lockfile-only requirements update strategy set" do
      let(:requirements_update_strategy) { Dependabot::RequirementsUpdateStrategy::LockfileOnly }

      it { is_expected.to be(false) }
    end
  end
end
