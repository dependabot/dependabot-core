# frozen_string_literal: true

require "spec_helper"
require "shared_contexts"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bundler/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Bundler::UpdateChecker do
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
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency_files) { bundler_project_dependency_files("gemfile") }

  let(:github_token) { "token" }
  let(:directory) { "/" }
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: current_version,
      requirements: requirements,
      package_manager: "bundler"
    )
  end
  let(:dependency_name) { "business" }
  let(:current_version) { "1.4.0" }
  let(:requirements) do
    [{ file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }]
  end

  let(:rubygems_url) { "https://rubygems.org/api/v1/" }

  describe "#latest_version" do
    subject { checker.latest_version }

    context "with a rubygems source" do
      before do
        rubygems_response = fixture("ruby", "rubygems_response_versions.json")
        stub_request(:get, rubygems_url + "versions/business.json").
          to_return(status: 200, body: rubygems_response)
      end

      it { is_expected.to eq(Gem::Version.new("1.5.0")) }

      context "that only appears in the lockfile" do
        let(:dependency_files) { bundler_project_dependency_files("subdependency") }

        let(:requirements) { [] }
        let(:dependency_name) { "i18n" }
        let(:current_version) { "0.7.0.beta1" }

        before do
          rubygems_response = fixture("ruby", "rubygems_response_versions.json")
          stub_request(:get, rubygems_url + "versions/i18n.json").
            to_return(status: 200, body: rubygems_response)
        end

        it { is_expected.to eq(Gem::Version.new("1.6.0.beta")) }
      end

      context "when the gem isn't on Rubygems" do
        before do
          stub_request(:get, rubygems_url + "versions/business.json").
            to_return(status: 404, body: "This rubygem could not be found.")
        end

        it { is_expected.to be_nil }
      end

      context "with a Gemfile that includes a file with require_relative" do
        let(:dependency_files) { bundler_project_dependency_files("includes_require_relative_gemfile") }
        let(:directory) { "app/" }

        it { is_expected.to eq(Gem::Version.new("1.5.0")) }
      end

      context "with a gem.rb and gems.locked setup" do
        let(:dependency_files) { bundler_project_dependency_files("gems_rb") }

        let(:requirements) do
          [{
            file: "gems.rb",
            requirement: "~> 1.4.0",
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to eq(Gem::Version.new("1.5.0")) }
      end
    end

    context "with extra nonrelevant credentials" do
      before do
        rubygems_response = fixture("ruby", "rubygems_response_versions.json")
        stub_request(:get, rubygems_url + "versions/business.json").
          to_return(status: 200, body: rubygems_response)
      end

      let(:credentials) do
        [{
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }, {
          "type" => "npm_registry",
          "registry" => "npm.fury.io/dependabot",
          "token" => "secret_token"
        }]
      end

      it { is_expected.to eq(Gem::Version.new("1.5.0")) }
    end

    context "with a private rubygems source" do
      let(:dependency_files) { bundler_project_dependency_files("specified_source") }

      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: ">= 0",
          groups: [],
          source: { type: "rubygems" }
        }]
      end
      let(:registry_url) { "https://repo.fury.io/greysteil/" }
      let(:gemfury_business_url) do
        "https://repo.fury.io/greysteil/api/v1/dependencies?gems=business"
      end
      before do
        bundler_version = PackageManagerHelper.bundler_version

        # We only need to stub out the version callout since it would
        # otherwise call out to the internet in a shell command
        allow(Dependabot::Bundler::NativeHelpers).
          to receive(:run_bundler_subprocess).
          with({
            bundler_version: bundler_version,
            function: "dependency_source_type",
            options: anything,
            args: anything
          }).and_call_original

        allow(Dependabot::Bundler::NativeHelpers).
          to receive(:run_bundler_subprocess).
          with({
            bundler_version: bundler_version,
            function: "private_registry_versions",
            options: anything,
            args: anything
          }).
          and_return(
            ["1.5.0", "1.9.0", "1.10.0.beta"]
          )
      end

      it { is_expected.to eq(Gem::Version.new("1.9.0")) }
    end

    context "given a git source" do
      let(:dependency_files) { bundler_project_dependency_files("git_source_no_ref") }

      before do
        rubygems_response = fixture("ruby", "rubygems_response_versions.json")
        stub_request(:get, rubygems_url + "versions/business.json").
          to_return(status: 200, body: rubygems_response)
      end

      context "that is the gem we're checking for" do
        let(:dependency_name) { "business" }
        let(:current_version) { "a1b78a929dac93a52f08db4f2847d76d6cfe39bd" }
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: ">= 0",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/dependabot-fixtures/business",
              branch: "master",
              ref: "master"
            }
          }]
        end

        context "when head of the gem's branch is included in a release" do
          before do
            allow_any_instance_of(Dependabot::GitCommitChecker).
              to receive(:branch_or_ref_in_release?).
              and_return(true)
          end

          it { is_expected.to eq(Gem::Version.new("1.5.0")) }
        end

        context "when head of the gem's branch is not included in a release" do
          before do
            allow_any_instance_of(Dependabot::GitCommitChecker).
              to receive(:branch_or_ref_in_release?).
              and_return(false)
            git_url = "https://github.com/dependabot-fixtures/business.git"
            git_header = {
              "content-type" => "application/x-git-upload-pack-advertisement"
            }
            stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
              to_return(
                status: 200,
                body: fixture("git", "upload_packs", "business"),
                headers: git_header
              )
          end

          it "fetches the latest SHA-1 hash" do
            expect(checker.latest_version).
              to eq("7bb4e41ce5164074a0920d5b5770d196b4d90104")
          end
        end

        context "when the gem's tag is pinned" do
          let(:dependency_files) { bundler_project_dependency_files("git_source") }

          let(:requirements) do
            [{
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/dependabot-fixtures/business",
                branch: "master",
                ref: "a1b78a9"
              }
            }]
          end

          context "and the gem isn't on Rubygems" do
            before do
              stub_request(:get, rubygems_url + "versions/business.json").
                to_return(status: 404, body: "This rubygem could not be found.")
            end

            it { is_expected.to eq(current_version) }
          end

          context "and the reference isn't included in the new version" do
            before do
              allow_any_instance_of(Dependabot::GitCommitChecker).
                to receive(:branch_or_ref_in_release?).
                and_return(false)
            end

            it "respects the pin" do
              expect(checker.latest_version).to eq(current_version)
              expect(checker.can_update?(requirements_to_unlock: :own)).
                to eq(false)
            end
          end

          context "and the reference is included in the new version" do
            before do
              allow_any_instance_of(Dependabot::GitCommitChecker).
                to receive(:branch_or_ref_in_release?).
                and_return(true)
            end

            it { is_expected.to eq(Gem::Version.new("1.5.0")) }
          end

          context "and the pin looks like a version" do
            let(:requirements) do
              [{
                file: "Gemfile",
                requirement: ">= 0",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/dependabot-fixtures/business",
                  branch: "master",
                  ref: "v1.0.0"
                }
              }]
            end

            before do
              stub_request(:get, rubygems_url + "versions/business.json").
                to_return(status: 404, body: "This rubygem could not be found.")
              url = "https://github.com/dependabot-fixtures/business.git"
              git_header = {
                "content-type" => "application/x-git-upload-pack-advertisement"
              }
              stub_request(:get, url + "/info/refs?service=git-upload-pack").
                with(basic_auth: %w(x-access-token token)).
                to_return(
                  status: 200,
                  body: fixture("git", "upload_packs", upload_pack_fixture),
                  headers: git_header
                )
            end
            let(:upload_pack_fixture) { "business" }

            it "fetches the latest SHA-1 hash of the latest version tag" do
              expect(checker.latest_version).
                to eq("37f41032a0f191507903ebbae8a5c0cb945d7585")
            end

            context "but there are no tags" do
              let(:upload_pack_fixture) { "no_tags" }

              it "returns the current version" do
                expect(checker.latest_version).to eq(current_version)
              end
            end
          end
        end
      end
    end

    context "given a path source" do
      let(:dependency_files) { bundler_project_dependency_files("path_source") }

      before do
        rubygems_response = fixture("ruby", "rubygems_response_versions.json")
        stub_request(:get, rubygems_url + "versions/business.json").
          to_return(status: 200, body: rubygems_response)
      end

      context "with a downloaded gemspec" do
        context "that is the gem we're checking" do
          let(:dependency_name) { "example" }
          let(:current_version) { "0.9.3" }
          let(:requirements) do
            [{
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: { type: "path" }
            }]
          end

          it { is_expected.to be_nil }
        end
      end
    end
  end

  describe "#lowest_security_fix_version" do
    subject { checker.lowest_security_fix_version }

    context "with a rubygems source" do
      let(:current_version) { "1.2.0" }
      let(:requirements) do
        [{ file: "Gemfile", requirement: "~> 1.2.0", groups: [], source: nil }]
      end

      before do
        rubygems_response = fixture("ruby", "rubygems_response_versions.json")
        stub_request(:get, rubygems_url + "versions/business.json").
          to_return(status: 200, body: rubygems_response)
      end

      it "finds the lowest available non-vulnerable version" do
        is_expected.to eq(Gem::Version.new("1.3.0"))
      end

      context "with a security vulnerability" do
        let(:security_advisories) do
          [
            Dependabot::SecurityAdvisory.new(
              dependency_name: dependency_name,
              package_manager: "bundler",
              vulnerable_versions: ["<= 1.3.0"]
            )
          ]
        end

        it "finds the lowest available non-vulnerable version" do
          is_expected.to eq(Gem::Version.new("1.4.0"))
        end
      end
    end
  end

  describe "#latest_version_resolvable_with_full_unlock?" do
    include_context "stub rubygems compact index"
    subject { checker.send(:latest_version_resolvable_with_full_unlock?) }

    context "with no latest version" do
      before do
        stub_request(:get, rubygems_url + "versions/business.json").
          to_return(status: 404, body: "This rubygem could not be found.")
      end

      it { is_expected.to be_falsey }
    end

    context "with a latest version" do
      before do
        allow(checker).
          to receive(:latest_version).
          and_return(target_version)
      end

      context "when the force updater raises" do
        let(:dependency_files) { bundler_project_dependency_files("subdep_blocked_by_subdep") }
        let(:target_version) { "2.0.0" }
        let(:dependency_name) { "dummy-pkg-a" }
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 1.0.0",
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to be_falsey }
      end

      context "when the force updater succeeds" do
        let(:dependency_files) { bundler_project_dependency_files("version_conflict") }
        let(:target_version) { "3.6.0" }
        let(:dependency_name) { "rspec-mocks" }
        let(:requirements) do
          [{ file: "Gemfile", requirement: "3.5.0", groups: [], source: nil }]
        end

        it { is_expected.to be_truthy }
      end
    end
  end

  describe "#updated_dependencies_after_full_unlock" do
    include_context "stub rubygems compact index"
    subject(:updated_dependencies_after_full_unlock) do
      checker.send(:updated_dependencies_after_full_unlock)
    end

    context "with a latest version" do
      before do
        allow(checker).to receive(:latest_version).and_return(target_version)
      end

      context "when the force updater succeeds" do
        let(:dependency_files) { bundler_project_dependency_files("version_conflict") }
        let(:target_version) { "3.6.0" }
        let(:dependency_name) { "rspec-mocks" }
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: "3.5.0",
            groups: [:default],
            source: nil
          }]
        end
        let(:expected_requirements) do
          [{
            file: "Gemfile",
            requirement: "3.6.0",
            groups: [:default],
            source: nil
          }]
        end

        it "returns the right array of updated dependencies" do
          expect(updated_dependencies_after_full_unlock).to match_array(
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

        context "with a gem.rb and gems.locked setup" do
          let(:dependency_files) { bundler_project_dependency_files("version_conflict_gems_rb") }

          let(:requirements) do
            [{
              file: "gems.rb",
              requirement: "3.5.0",
              groups: [:default],
              source: nil
            }]
          end
          let(:expected_requirements) do
            [{
              file: "gems.rb",
              requirement: "3.6.0",
              groups: [:default],
              source: nil
            }]
          end

          it "returns the right array of updated dependencies" do
            expect(updated_dependencies_after_full_unlock).to match_array(
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
      end
    end
  end

  describe "#conflicting_dependencies" do
    include_context "stub rubygems compact index"
    include_context "stub rubygems versions api"

    subject { checker.conflicting_dependencies }

    let(:dependency_files) { bundler_project_dependency_files("subdep_blocked_by_subdep") }
    let(:target_version) { "2.0.0" }
    let(:dependency_name) { "dummy-pkg-a" }
    let(:requirements) do
      [{
        file: "Gemfile",
        requirement: "~> 1.0.0",
        groups: [],
        source: nil
      }]
    end

    let(:requirements) { [] }
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "bundler",
          vulnerable_versions: ["< 2.0.0"]
        )
      ]
    end

    before do
      allow(checker).
        to receive(:lowest_security_fix_version).
        and_return(target_version)
    end

    it do
      is_expected.to eq(
        [{
          "explanation" => "dummy-pkg-b (1.0.0) requires dummy-pkg-a (< 2.0.0)",
          "name" => "dummy-pkg-b",
          "version" => "1.0.0",
          "requirement" => "< 2.0.0"
        }]
      )
    end
  end

  describe "#latest_resolvable_version" do
    include_context "stub rubygems compact index"
    include_context "stub rubygems versions api"

    subject { checker.latest_resolvable_version }

    context "given a gem from rubygems" do
      context "that only appears in the lockfile" do
        let(:dependency_files) { bundler_project_dependency_files("subdependency") }
        let(:requirements) { [] }
        let(:dependency_name) { "i18n" }
        let(:current_version) { "0.7.0.beta1" }

        it { is_expected.to eq(Gem::Version.new("0.7.0")) }
      end

      context "with no version specified" do
        let(:dependency_files) { bundler_project_dependency_files("version_not_specified") }
        let(:requirements) do
          [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
        end

        it { is_expected.to eq(Gem::Version.new("1.13.0")) }

        context "when the user is ignoring the latest version" do
          let(:ignored_versions) { [">= 1.7.0.a, < 2.0"] }
          it { is_expected.to eq(Gem::Version.new("1.6.0")) }
        end
      end

      context "with a greater than or equal to matcher" do
        let(:dependency_files) { bundler_project_dependency_files("gte_matcher") }
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: ">= 1.4.0",
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to eq(Gem::Version.new("1.13.0")) }
      end

      context "with multiple requirements" do
        let(:dependency_files) { bundler_project_dependency_files("version_between_bounds_gemfile") }
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: "> 1.0.0, < 1.5.0",
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to eq(Gem::Version.new("1.13.0")) }
      end

      context "with a gem.rb and gems.locked setup" do
        context "that only appears in the lockfile" do
          let(:dependency_files) { bundler_project_dependency_files("subdependency_gems_rb") }
          let(:requirements) { [] }
          let(:dependency_name) { "i18n" }
          let(:current_version) { "0.7.0.beta1" }

          it { is_expected.to eq(Gem::Version.new("0.7.0")) }
        end

        context "with a range requirement" do
          let(:dependency_files) { bundler_project_dependency_files("version_between_bounds_gems_rb") }
          let(:requirements) do
            [{
              file: "gems.rb",
              requirement: "> 1.0.0, < 1.5.0",
              groups: [],
              source: nil
            }]
          end

          it { is_expected.to eq(Gem::Version.new("1.13.0")) }
        end
      end
    end

    context "given a gem with a path source" do
      context "with a downloaded gemspec" do
        let(:dependency_files) { bundler_project_dependency_files("path_source_no_overlap") }

        it { is_expected.to eq(Gem::Version.new("1.13.0")) }

        it "doesn't persist any temporary changes to Bundler's root" do
          expect { checker.latest_resolvable_version }.
            to_not(change { ::Bundler.root })
        end

        context "that requires other files" do
          let(:dependency_files) { bundler_project_dependency_files("path_source_no_overlap_with_require") }

          it { is_expected.to eq(Gem::Version.new("1.13.0")) }
        end

        context "that is the gem we're checking" do
          let(:dependency_name) { "example" }
          let(:current_version) { "0.9.3" }
          it { is_expected.to eq(Gem::Version.new("0.9.3")) }
        end

        context "that has a .specification" do
          let(:dependency_files) { bundler_project_dependency_files("path_source_statesman") }

          it { is_expected.to eq(Gem::Version.new("1.13.0")) }
        end
      end
    end

    context "given a gem with a git source" do
      let(:dependency_files) { bundler_project_dependency_files("git_source_no_ref") }

      context "that is the gem we're checking" do
        let(:dependency_name) { "business" }
        let(:current_version) { "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2" }
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: ">= 0",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/dependabot-fixtures/business",
              branch: "master",
              ref: "master"
            }
          }]
        end

        context "when the head of the branch isn't released" do
          before do
            allow_any_instance_of(Dependabot::GitCommitChecker).
              to receive(:branch_or_ref_in_release?).
              and_return(false)
            git_url = "https://github.com/dependabot-fixtures/business.git"
            git_header = {
              "content-type" => "application/x-git-upload-pack-advertisement"
            }
            stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
              to_return(
                status: 200,
                body: fixture("git", "upload_packs", "business"),
                headers: git_header
              )
          end

          it "fetches the latest SHA-1 hash" do
            version = checker.latest_resolvable_version
            expect(version).to match(/^[0-9a-f]{40}$/)
            expect(version).to_not eq(current_version)
          end

          context "and the Gemfile doesn't specify a git source" do
            let(:dependency_files) { bundler_project_dependency_files("git_source_mismatched") }

            # If the dependency has a git version in the Gemfile.lock but not in
            # the Gemfile (i.e., because they're out-of-sync) we leave that
            # problem to the user.
            it { is_expected.to be_nil }
          end
        end

        context "when the head of the branch is released" do
          before do
            allow_any_instance_of(Dependabot::GitCommitChecker).
              to receive(:branch_or_ref_in_release?).
              and_return(true)
          end

          it { is_expected.to eq(Gem::Version.new("1.13.0")) }
        end

        context "when the dependency has never been released" do
          let(:dependency_files) { bundler_project_dependency_files("git_source") }
          let(:current_version) { "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2" }
          let(:requirements) do
            [{
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/dependabot-fixtures/prius",
                branch: "master",
                ref: "master"
              }
            }]
          end

          before do
            allow_any_instance_of(Dependabot::GitCommitChecker).
              to receive(:branch_or_ref_in_release?).
              and_return(false)
            git_url = "https://github.com/dependabot-fixtures/prius.git"
            git_header = {
              "content-type" => "application/x-git-upload-pack-advertisement"
            }
            stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
              to_return(
                status: 200,
                body: fixture("git", "upload_packs", "prius"),
                headers: git_header
              )
          end

          it "fetches the latest SHA-1 hash" do
            version = checker.latest_resolvable_version
            expect(version).to match(/^[0-9a-f]{40}$/)
            expect(version).to_not eq(current_version)
          end
        end

        context "when the gem's tag is pinned" do
          let(:dependency_files) { bundler_project_dependency_files("git_source") }
          let(:dependency_name) { "business" }
          let(:current_version) { "a1b78a929dac93a52f08db4f2847d76d6cfe39bd" }

          let(:requirements) do
            [{
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/dependabot-fixtures/business",
                branch: "master",
                ref: "a1b78a9"
              }
            }]
          end

          context "and the reference isn't included in the new version" do
            before do
              allow_any_instance_of(Dependabot::GitCommitChecker).
                to receive(:branch_or_ref_in_release?).
                and_return(false)
            end

            it "respects the pin" do
              expect(checker.latest_resolvable_version).
                to eq("a1b78a929dac93a52f08db4f2847d76d6cfe39bd")
              expect(checker.can_update?(requirements_to_unlock: :own)).
                to eq(false)
            end
          end

          context "and the reference is included in the new version" do
            before do
              allow_any_instance_of(Dependabot::GitCommitChecker).
                to receive(:branch_or_ref_in_release?).
                and_return(true)
            end

            it { is_expected.to eq(Gem::Version.new("1.13.0")) }
          end

          context "and the release looks like a version" do
            let(:requirements) do
              [{
                file: "Gemfile",
                requirement: ">= 0",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/dependabot-fixtures/business",
                  branch: "master",
                  ref: "v1.0.0"
                }
              }]
            end

            before do
              stub_request(:get, rubygems_url + "versions/business.json").
                to_return(status: 404, body: "This rubygem could not be found.")
              url = "https://github.com/dependabot-fixtures/business.git"
              git_header = {
                "content-type" => "application/x-git-upload-pack-advertisement"
              }
              stub_request(:get, url + "/info/refs?service=git-upload-pack").
                with(basic_auth: %w(x-access-token token)).
                to_return(
                  status: 200,
                  body: fixture("git", "upload_packs", upload_pack_fixture),
                  headers: git_header
                )
            end
            let(:upload_pack_fixture) { "business" }

            it "fetches the latest SHA-1 hash of the latest version tag" do
              expect(checker.latest_resolvable_version).
                to eq("37f41032a0f191507903ebbae8a5c0cb945d7585")
            end

            context "but this dependency has never been released" do
              let(:dependency_files) { bundler_project_dependency_files("git_source_unreleased") }
              let(:dependency_name) { "dummy-git-dependency" }
              let(:current_version) do
                "20151f9b67c8a04461fa0ee28385b6187b86587b"
              end
              let(:upload_pack_fixture) { "dummy-git-dependency" }
              let(:requirements) do
                [{
                  file: "Gemfile",
                  requirement: ">= 0",
                  groups: [],
                  source: {
                    type: "git",
                    url: "https://github.com/dependabot-fixtures/" \
                         "ruby-dummy-git-dependency",
                    branch: nil,
                    ref: "v1.0.0"
                  }
                }]
              end

              before do
                stub_request(
                  :get, rubygems_url + "versions/dummy-git-dependency.json"
                ).to_return(status: 404)
                url = "https://github.com/dependabot-fixtures/" \
                      "ruby-dummy-git-dependency.git"
                git_header = {
                  "content-type" =>
                    "application/x-git-upload-pack-advertisement"
                }
                stub_request(:get, url + "/info/refs?service=git-upload-pack").
                  with(basic_auth: %w(x-access-token token)).
                  to_return(
                    status: 200,
                    body: fixture("git", "upload_packs", upload_pack_fixture),
                    headers: git_header
                  )
              end

              it "returns the commit SHA for the updated version" do
                expect(checker.latest_resolvable_version).
                  to eq("c0e25c2eb332122873f73acb3b61fb2e261cfd8f")
              end
            end

            context "but there are no tags" do
              let(:upload_pack_fixture) { "no_tags" }

              it "returns the current version" do
                expect(checker.latest_resolvable_version).to eq(current_version)
              end
            end

            context "when updating the gem results in a conflict" do
              let(:dependency_files) { bundler_project_dependency_files("git_source_with_tag_conflict") }

              before do
                allow_any_instance_of(Dependabot::GitCommitChecker).
                  to receive(:branch_or_ref_in_release?).
                  and_return(false)
                refs_url = "https://github.com/hvssle/onfido.git/info/refs"
                git_header = {
                  "content-type" =>
                    "application/x-git-upload-pack-advertisement"
                }
                stub_request(:get, refs_url + "?service=git-upload-pack").
                  to_return(
                    status: 200,
                    body: fixture("git", "upload_packs", "onfido"),
                    headers: git_header
                  )
              end

              let(:dependency_name) { "onfido" }
              let(:current_version) do
                "7b36eac82a7e42049052a58af0a7943fe0363714"
              end

              let(:requirements) do
                [{
                  file: "Gemfile",
                  requirement: ">= 0",
                  groups: [],
                  source: {
                    type: "git",
                    url: "https://github.com/hvssle/onfido",
                    branch: "master",
                    ref: "v0.4.0"
                  }
                }]
              end

              it { is_expected.to eq(dependency.version) }
            end
          end
        end

        context "when the gem has a version specified, too" do
          let(:dependency_files) { bundler_project_dependency_files("git_source_with_version_gemfile") }

          let(:requirements) do
            [{
              file: "Gemfile",
              requirement: "~> 1.0.0",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/dependabot-fixtures/" \
                     "dependabot-test-ruby-package",
                branch: "master",
                ref: "master"
              }
            }]
          end
          let(:dependency_name) { "dependabot-test-ruby-package" }
          let(:current_version) { "81073f9462f228c6894e3e384d0718def310d99f" }

          before do
            allow_any_instance_of(Dependabot::GitCommitChecker).
              to receive(:branch_or_ref_in_release?).
              and_return(false)
            stub_request(
              :get, rubygems_url + "versions/dependabot-test-ruby-package.json"
            ).to_return(status: 404)
            git_url = "https://github.com/dependabot-fixtures/" \
                      "dependabot-test-ruby-package.git"
            git_header = {
              "content-type" => "application/x-git-upload-pack-advertisement"
            }
            stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
              to_return(
                status: 200,
                body: fixture("git",
                              "upload_packs",
                              "dependabot-test-ruby-package"),
                headers: git_header
              )
          end

          it "fetches the latest SHA-1 hash" do
            version = checker.latest_resolvable_version
            expect(version).to match(/^[0-9a-f]{40}$/)
            expect(version).to_not eq "c5bf1bd47935504072ac0eba1006cf4d67af6a7a"
          end
        end

        context "when the gem has a bad branch" do
          let(:dependency_files) { bundler_project_dependency_files("bad_branch") }
          around { |example| capture_stderr { example.run } }

          let(:dependency_name) { "prius" }
          let(:current_version) { "2.0.0" }
          let(:requirements) do
            [{
              file: "Gemfile",
              requirement: "~> 1.0.0",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/dependabot-fixtures/prius",
                branch: "master",
                ref: "master"
              }
            }]
          end

          before do
            allow_any_instance_of(Dependabot::GitCommitChecker).
              to receive(:branch_or_ref_in_release?).
              and_return(false)
            git_url = "https://github.com/dependabot-fixtures/prius.git"
            git_header = {
              "content-type" => "application/x-git-upload-pack-advertisement"
            }
            stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
              to_return(
                status: 200,
                body: fixture("git", "upload_packs", "prius"),
                headers: git_header
              )
            allow(checker).
              to receive(:latest_resolvable_version_details).
              and_call_original
            allow(checker).
              to receive(:latest_resolvable_version_details).
              with(remove_git_source: true).
              and_return(version: Gem::Version.new("2.0.0"))
          end

          it "raises a helpful error" do
            expect { checker.latest_resolvable_version }.
              to raise_error do |error|
                expect(error).to be_a Dependabot::GitDependencyReferenceNotFound
                expect(error.dependency).to eq("prius")
              end
          end
        end

        context "when updating the gem results in a conflict" do
          let(:dependency_files) { bundler_project_dependency_files("git_source_with_conflict") }
          around { |example| capture_stderr { example.run } }

          before do
            allow_any_instance_of(Dependabot::GitCommitChecker).
              to receive(:branch_or_ref_in_release?).
              and_return(false)
            git_url = "https://github.com/hvssle/onfido.git"
            git_header = {
              "content-type" => "application/x-git-upload-pack-advertisement"
            }
            stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
              to_return(
                status: 200,
                body: fixture("git", "upload_packs", "onfido"),
                headers: git_header
              )
            allow(checker).
              to receive(:latest_resolvable_version_details).
              and_call_original
            allow(checker).
              to receive(:latest_resolvable_version_details).
              with(remove_git_source: true).
              and_return(version: Gem::Version.new("2.0.0"))
          end

          let(:dependency_name) { "onfido" }
          let(:current_version) { "1.13.0" }
          let(:requirements) do
            [{
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/hvssle/onfido",
                branch: "master",
                ref: "master"
              }
            }]
          end

          it { is_expected.to be_nil }
        end
      end

      context "that is not the gem we're checking" do
        let(:dependency_files) { bundler_project_dependency_files("git_source") }
        let(:dependency_name) { "statesman" }
        let(:current_version) { "1.2" }

        it { is_expected.to eq(Gem::Version.new("3.4.1")) }

        context "that is private" do
          let(:dependency_files) { bundler_project_dependency_files("private_git_source") }
          let(:token) do
            Base64.encode64("x-access-token:#{github_token}").delete("\n")
          end
          around { |example| capture_stderr { example.run } }

          before do
            stub_request(
              :get,
              "https://github.com/no-exist-sorry/prius.git/info/refs" \
              "?service=git-upload-pack"
            ).with(headers: { "Authorization" => "Basic #{token}" }).
              to_return(status: 401)
          end

          it "raises a helpful error on bundler v1", :bundler_v1_only do
            expect { checker.latest_resolvable_version }.
              to raise_error do |error|
                expect(error).to be_a(Dependabot::GitDependenciesNotReachable)
                expect(error.dependency_urls).
                  to eq(["git@github.com:no-exist-sorry/prius"])
              end
          end

          context "bundler v2", :bundler_v2_only do
            let(:dependency_files) { bundler_project_dependency_files("private_git_source") }

            it "updates the dependency" do
              expect(checker.latest_resolvable_version).to eq(Gem::Version.new("3.4.1"))
            end
          end
        end

        context "that has a bad reference" do
          let(:dependency_files) { bundler_project_dependency_files("bad_ref") }
          around { |example| capture_stderr { example.run } }

          before do
            stub_request(:get, "https://github.com/dependabot-fixtures/prius").
              to_return(status: 200)
          end

          it "raises a helpful error", :bundler_v1_only do
            expect { checker.latest_resolvable_version }.
              to raise_error do |error|
                expect(error).to be_a Dependabot::GitDependencyReferenceNotFound
                expect(error.dependency).to eq("prius")
              end
          end

          context "bundler v2", :bundler_v2_only do
            let(:dependency_files) { bundler_project_dependency_files("bad_ref") }

            it "updates the dependency" do
              expect(checker.latest_resolvable_version).to eq(Gem::Version.new("3.4.1"))
            end
          end
        end

        context "that has a bad branch" do
          let(:dependency_files) { bundler_project_dependency_files("bad_branch") }

          it { is_expected.to eq(Gem::Version.new("3.4.1")) }
        end
      end
    end

    context "given a Gemfile that specifies a Ruby version" do
      let(:dependency_files) { bundler_project_dependency_files("explicit_ruby") }
      let(:dependency_name) { "statesman" }
      let(:requirements) do
        [{ file: "Gemfile", requirement: "~> 1.2.0", groups: [], source: nil }]
      end

      it { is_expected.to eq(Gem::Version.new("3.4.1")) }

      context "that is old" do
        let(:dependency_files) { bundler_project_dependency_files("explicit_ruby_old") }

        xit { is_expected.to eq(Gem::Version.new("2.0.1")) }
      end
    end

    context "with a gemspec and a Gemfile" do
      let(:dependency_files) { bundler_project_dependency_files("imports_gemspec_small_example_no_lockfile") }
      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: "~> 1.2.0",
          groups: [],
          source: nil
        }, {
          file: "example.gemspec",
          requirement: "~> 1.0",
          groups: [],
          source: nil
        }]
      end

      it "doesn't just fall back to latest_version" do
        expect(checker.latest_resolvable_version).
          to eq(Gem::Version.new("1.13.0"))
      end

      context "when the gemspec has a path" do
        let(:dependency_files) { bundler_project_dependency_files("imports_gemspec_from_path") }
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 1.2.0",
            groups: [],
            source: nil
          }, {
            file: "subdir/example.gemspec",
            requirement: "~> 1.0",
            groups: [],
            source: nil
          }]
        end

        it "doesn't just fall back to latest_version" do
          expect(checker.latest_resolvable_version).
            to eq(Gem::Version.new("1.13.0"))
        end
      end

      context "when an old required ruby is specified in the gemspec" do
        let(:dependency_files) { bundler_project_dependency_files("imports_gemspec_old_required_ruby_no_lockfile") }
        let(:dependency_name) { "statesman" }

        it "takes the minimum ruby version into account" do
          expect(checker.latest_resolvable_version).
            to eq(Gem::Version.new("2.0.1"))
        end
      end

      context "when the Gemfile doesn't import the gemspec" do
        let(:dependency_files) { bundler_project_dependency_files("gemspec_not_imported_no_lockfile") }

        it "falls back to latest_version" do
          expect(checker.latest_resolvable_version).
            to eq(Gem::Version.new("1.13.0"))
        end
      end
    end

    context "with only a gemspec" do
      let(:dependency_files) { bundler_project_dependency_files("gemspec_small_example_no_lockfile") }

      it "falls back to latest_version" do
        dummy_version_resolver =
          checker.send(:version_resolver, remove_git_source: false)
        dummy_version = Gem::Version.new("0.5.0")
        allow(checker).
          to receive(:version_resolver).
          and_return(dummy_version_resolver)
        expect(dummy_version_resolver).
          to receive(:latest_version_details).
          and_return(version: dummy_version)
        expect(checker.latest_resolvable_version).to eq(dummy_version)
      end
    end

    context "with only a Gemfile" do
      let(:dependency_files) { bundler_project_dependency_files("no_lockfile") }

      it "doesn't just fall back to latest_version" do
        expect(checker.latest_resolvable_version).
          to eq(Gem::Version.new("1.13.0"))
      end

      context "given a gem with a private git source" do
        let(:dependency_files) { bundler_project_dependency_files("private_git_source_no_lockfile") }
        let(:token) do
          Base64.encode64("x-access-token:#{github_token}").delete("\n")
        end
        around { |example| capture_stderr { example.run } }

        before do
          stub_request(
            :get,
            "https://github.com/dependabot-fixtures/does-not-exist.git/info/refs" \
            "?service=git-upload-pack"
          ).with(headers: { "Authorization" => "Basic #{token}" }).
            to_return(status: 401)
        end

        it "raises a helpful error" do
          expect { checker.latest_resolvable_version }.
            to raise_error do |error|
              expect(error).to be_a(Dependabot::GitDependenciesNotReachable)
              expect(error.dependency_urls).
                to eq(["git@github.com:dependabot-fixtures/does-not-exist"])
            end
        end
      end

      context "given a gem with a private github source" do
        let(:dependency_files) { bundler_project_dependency_files("private_github_source_no_lockfile") }
        let(:token) do
          Base64.encode64("x-access-token:#{github_token}").delete("\n")
        end
        around { |example| capture_stderr { example.run } }

        before do
          stub_request(
            :get,
            "https://github.com/dependabot-fixtures/does-not-exist.git/info/refs" \
            "?service=git-upload-pack"
          ).with(headers: { "Authorization" => "Basic #{token}" }).
            to_return(status: 401)
        end

        it "raises a helpful error", :bundler_v2_only do
          expect { checker.latest_resolvable_version }.
            to raise_error do |error|
              expect(error).to be_a(Dependabot::GitDependenciesNotReachable)
              expect(error.dependency_urls).
                to eq(["https://github.com/dependabot-fixtures/does-not-exist.git"])
            end
        end
      end

      context "when the git request raises a timeout" do
        let(:dependency_files) { bundler_project_dependency_files("private_git_source_no_lockfile") }
        let(:token) do
          Base64.encode64("x-access-token:#{github_token}").delete("\n")
        end
        around { |example| capture_stderr { example.run } }

        before do
          stub_request(
            :get,
            "https://github.com/dependabot-fixtures/does-not-exist.git/info/refs" \
            "?service=git-upload-pack"
          ).with(headers: { "Authorization" => "Basic #{token}" }).
            to_raise(Excon::Error::Timeout)
        end

        it "raises a helpful error" do
          expect { checker.latest_resolvable_version }.
            to raise_error do |error|
              expect(error).to be_a(Dependabot::GitDependenciesNotReachable)
              expect(error.dependency_urls).
                to eq(["git@github.com:dependabot-fixtures/does-not-exist"])
            end
        end
      end
    end

    context "with a gem that depends on bundler" do
      let(:dependency_files) { bundler_project_dependency_files("guard_bundler") }
      let(:requirements) do
        [{ file: "Gemfile", requirement: "~> 2.2.1, <= 3.0.0", groups: [], source: nil }]
      end
      let(:dependency_name) { "guard-bundler" }
      let(:current_version) { "2.2.1" }

      context "using bundler v1", :bundler_v1_only do
        it { is_expected.to eq(Gem::Version.new("2.2.1")) }
      end

      context "using bundler v2", :bundler_v2_only do
        it { is_expected.to eq(Gem::Version.new("3.0.0")) }
      end
    end
  end

  describe "#preferred_resolvable_version" do
    include_context "stub rubygems compact index"
    include_context "stub rubygems versions api"

    subject { checker.preferred_resolvable_version }

    it { is_expected.to eq(Gem::Version.new("1.13.0")) }

    context "with a security vulnerability" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "bundler",
            vulnerable_versions: ["<= 1.4.0"]
          )
        ]
      end

      it { is_expected.to eq(Gem::Version.new("1.5.0")) }
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    include_context "stub rubygems compact index"
    include_context "stub rubygems versions api"

    subject { checker.latest_resolvable_version_with_no_unlock }

    context "given a gem from rubygems" do
      it { is_expected.to eq(Gem::Version.new("1.4.0")) }

      context "with a version conflict at the latest version" do
        let(:dependency_files) { bundler_project_dependency_files("version_conflict_no_req_change") }
        let(:dependency_name) { "ibandit" }
        let(:current_version) { "0.1.0" }
        let(:requirements) do
          [{ file: "Gemfile", requirement: "~> 0.1", groups: [], source: nil }]
        end

        # The latest version of ibandit is 0.8.5, but 0.3.4 is the latest
        # version compatible with the version of i18n in the Gemfile.
        it { is_expected.to eq(Gem::Version.new("0.3.4")) }
      end
    end

    context "with a sub-dependency" do
      let(:dependency_files) { bundler_project_dependency_files("subdependency") }
      let(:requirements) { [] }
      let(:dependency_name) { "i18n" }
      let(:current_version) { "0.7.0.beta1" }

      it { is_expected.to eq(Gem::Version.new("0.7.0")) }
    end
  end

  describe "#updated_requirements" do
    include_context "stub rubygems compact index"
    include_context "stub rubygems versions api"

    subject(:updated_requirements) { checker.updated_requirements }

    let(:requirements_updater) do
      Dependabot::Bundler::UpdateChecker::RequirementsUpdater
    end
    before do
      allow(requirements_updater).to receive(:new).and_call_original
    end

    context "with a Gemfile and a Gemfile.lock" do
      let(:dependency_files) { bundler_project_dependency_files("gemfile") }
      let(:dependency_name) { "business" }
      let(:current_version) { "1.4.0" }

      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: "~> 1.4.0",
          groups: [:default],
          source: nil
        }]
      end

      it "delegates to Bundler::RequirementsUpdater with the right params" do
        expect(requirements_updater).
          to receive(:new).with(
            requirements: requirements,
            update_strategy: :bump_versions,
            latest_version: "1.13.0",
            latest_resolvable_version: "1.13.0",
            updated_source: nil
          ).and_call_original

        expect(updated_requirements.count).to eq(1)
        expect(updated_requirements.first[:requirement]).to eq("~> 1.13.0")
      end

      context "with a security vulnerability" do
        let(:security_advisories) do
          [
            Dependabot::SecurityAdvisory.new(
              dependency_name: dependency_name,
              package_manager: "bundler",
              vulnerable_versions: ["<= 1.4.0"]
            )
          ]
        end

        it "delegates to Bundler::RequirementsUpdater with the right params" do
          expect(requirements_updater).
            to receive(:new).with(
              requirements: requirements,
              update_strategy: :bump_versions,
              latest_version: "1.13.0",
              latest_resolvable_version: "1.5.0",
              updated_source: nil
            ).and_call_original

          expect(updated_requirements.count).to eq(1)
          expect(updated_requirements.first[:requirement]).to eq("~> 1.5.0")
        end
      end

      context "with a sub-dependency" do
        let(:dependency_files) { bundler_project_dependency_files("subdependency") }
        let(:requirements) { [] }
        let(:dependency_name) { "i18n" }
        let(:current_version) { "0.7.0.beta1" }

        it { is_expected.to eq([]) }
      end

      context "with a gems.rb and gems.locked" do
        let(:dependency_files) { bundler_project_dependency_files("gems_rb") }

        let(:requirements) do
          [{
            file: "gems.rb",
            requirement: "~> 1.4.0",
            groups: [:default],
            source: nil
          }]
        end

        it "delegates to Bundler::RequirementsUpdater" do
          expect(requirements_updater).
            to receive(:new).with(
              requirements: requirements,
              update_strategy: :bump_versions,
              latest_version: "1.13.0",
              latest_resolvable_version: "1.13.0",
              updated_source: nil
            ).and_call_original

          expect(updated_requirements.count).to eq(1)
          expect(updated_requirements.first[:requirement]).to eq("~> 1.13.0")
          expect(updated_requirements.first[:file]).to eq("gems.rb")
        end
      end

      context "for a gem with a git source" do
        let(:dependency_files) { bundler_project_dependency_files("git_source_with_version_gemfile") }
        let(:dependency_name) { "dependabot-test-ruby-package" }
        let(:current_version) { "81073f9462f228c6894e3e384d0718def310d99f" }
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 1.0.0",
            groups: [:default],
            source: {
              type: "git",
              url: "https://github.com/dependabot-fixtures/" \
                   "dependabot-test-ruby-package",
              branch: "master",
              ref: "master"
            }
          }]
        end

        before do
          allow_any_instance_of(Dependabot::GitCommitChecker).
            to receive(:branch_or_ref_in_release?).
            and_return(false)
          stub_request(
            :get, rubygems_url + "versions/dependabot-test-ruby-package.json"
          ).to_return(status: 404)
          git_url = "https://github.com/dependabot-fixtures/" \
                    "dependabot-test-ruby-package.git"
          git_header = {
            "content-type" => "application/x-git-upload-pack-advertisement"
          }
          stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
            to_return(
              status: 200,
              body: fixture("git",
                            "upload_packs",
                            "dependabot-test-ruby-package"),
              headers: git_header
            )
        end

        it "delegates to Bundler::RequirementsUpdater with the right params" do
          expect(requirements_updater).
            to receive(:new).with(
              requirements: requirements,
              update_strategy: :bump_versions,
              latest_version: "1.0.1",
              latest_resolvable_version: "1.0.1",
              updated_source: requirements.first[:source]
            ).and_call_original

          expect(updated_requirements.count).to eq(1)
          expect(updated_requirements.first[:requirement]).
            to start_with("~> 1.")
        end

        context "that is pinned" do
          let(:dependency_files) { bundler_project_dependency_files("git_source") }

          let(:dependency_name) { "business" }
          let(:current_version) { "a1b78a929dac93a52f08db4f2847d76d6cfe39bd" }
          let(:requirements) do
            [{
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/dependabot-fixtures/business",
                branch: "master",
                ref: "a1b78a9"
              }
            }]
          end

          context "and the reference isn't included in the new version" do
            before do
              stub_request(:get, rubygems_url + "versions/business.json").
                to_return(status: 404, body: "This rubygem could not be found.")
            end

            it "delegates to Bundler::RequirementsUpdater" do
              expect(requirements_updater).
                to receive(:new).with(
                  requirements: requirements,
                  update_strategy: :bump_versions,
                  latest_version: /^2./,
                  latest_resolvable_version: /^1./,
                  updated_source: requirements.first[:source]
                ).and_call_original

              expect(updated_requirements.count).to eq(1)
              expect(updated_requirements.first[:requirement]).to eq(">= 0")
              expect(updated_requirements.first[:source]).to_not be_nil
            end
          end
        end
      end
    end

    context "with a Gemfile, a Gemfile.lock and a gemspec" do
      let(:dependency_files) { bundler_project_dependency_files("imports_gemspec") }
      let(:dependency_name) { "business" }
      let(:current_version) { "1.4.0" }

      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: "~> 1.4.0",
          groups: [:default],
          source: nil
        }, {
          file: "example.gemspec",
          requirement: "~> 1.0",
          groups: [:default],
          source: nil
        }]
      end

      it "delegates to Bundler::RequirementsUpdater with the right params" do
        expect(requirements_updater).
          to receive(:new).with(
            requirements: requirements,
            update_strategy: :bump_versions,
            latest_version: "1.13.0",
            latest_resolvable_version: "1.13.0",
            updated_source: requirements.first[:source]
          ).and_call_original

        expect(updated_requirements.count).to eq(2)
        expect(updated_requirements.first[:requirement]).to eq("~> 1.13.0")
        expect(updated_requirements.last[:requirement]).to eq("~> 1.0")
      end
    end

    context "with a Gemfile and a gemspec" do
      let(:dependency_files) { bundler_project_dependency_files("imports_gemspec_small_example_no_lockfile") }
      let(:dependency_name) { "business" }
      let(:current_version) { nil }

      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: "~> 1.4.0",
          groups: [:default],
          source: nil
        }, {
          file: "example.gemspec",
          requirement: "~> 1.0",
          groups: [:default],
          source: nil
        }]
      end

      it "delegates to Bundler::RequirementsUpdater with the right params" do
        expect(requirements_updater).
          to receive(:new).with(
            requirements: requirements,
            update_strategy: :bump_versions_if_necessary,
            latest_version: "1.13.0",
            latest_resolvable_version: "1.13.0",
            updated_source: requirements.first[:source]
          ).and_call_original

        expect(updated_requirements.count).to eq(2)
        expect(updated_requirements.first[:requirement]).to eq("~> 1.13.0")
        expect(updated_requirements.last[:requirement]).to eq("~> 1.0")
      end
    end

    context "with a Gemfile only" do
      let(:dependency_files) { bundler_project_dependency_files("no_lockfile") }
      let(:dependency_name) { "business" }
      let(:current_version) { nil }
      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: "~> 1.4.0",
          groups: [:default],
          source: nil
        }]
      end

      it "delegates to Bundler::RequirementsUpdater with the right params" do
        expect(requirements_updater).
          to receive(:new).with(
            requirements: requirements,
            update_strategy: :bump_versions_if_necessary,
            latest_version: "1.13.0",
            latest_resolvable_version: "1.13.0",
            updated_source: requirements.first[:source]
          ).and_call_original

        expect(updated_requirements.count).to eq(1)
        expect(updated_requirements.first[:requirement]).to eq("~> 1.13.0")
      end
    end

    context "with a gemspec only" do
      let(:dependency_files) { bundler_project_dependency_files("gemspec_no_lockfile") }
      let(:dependency_name) { "business" }
      let(:current_version) { nil }
      let(:requirements) do
        [{
          file: "example.gemspec",
          requirement: "~> 0.9",
          groups: ["runtime"],
          source: nil
        }]
      end

      it "delegates to Bundler::RequirementsUpdater with the right params" do
        expect(requirements_updater).
          to receive(:new).with(
            requirements: requirements,
            update_strategy: :bump_versions_if_necessary,
            latest_version: "1.13.0",
            latest_resolvable_version: "1.13.0",
            updated_source: requirements.first[:source]
          ).and_call_original

        expect(updated_requirements.count).to eq(1)
        expect(updated_requirements.first[:requirement]).to eq(">= 0.9, < 2.0")
      end
    end
  end

  describe "#requirements_unlocked_or_can_be?" do
    subject { checker.requirements_unlocked_or_can_be? }

    context "with a Gemfile dependency that is already unlocked" do
      let(:dependency_files) { bundler_project_dependency_files("version_not_specified") }
      let(:requirements) do
        [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
      end

      it { is_expected.to eq(true) }
    end

    context "with a sub-dependency" do
      let(:dependency_files) { bundler_project_dependency_files("subdependency") }
      let(:requirements) { [] }
      let(:dependency_name) { "i18n" }
      let(:current_version) { "0.7.0.beta1" }

      it { is_expected.to eq(true) }
    end

    context "with a Gemfile dependency that can be unlocked" do
      let(:dependency_files) { bundler_project_dependency_files("gemfile") }
      let(:requirements) do
        [{ file: "Gemfile", requirement: req, groups: [], source: nil }]
      end
      let(:req) { "~> 1.4.0" }

      it { is_expected.to eq(true) }

      context "with multiple requirements" do
        let(:dependency_files) { bundler_project_dependency_files("version_between_bounds_gemfile") }
        let(:req) { "> 1.0.0, < 1.5.0" }

        it { is_expected.to eq(true) }
      end
    end

    # For now we always let git dependencies through
    context "with a Gemfile dependency that is a git dependency" do
      let(:dependency_files) { bundler_project_dependency_files("git_source_no_ref") }
      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: ">= 0",
          groups: [],
          source: {
            type: "git",
            url: "https://github.com/dependabot-fixtures/business",
            branch: "master",
            ref: "master"
          }
        }]
      end

      it { is_expected.to eq(true) }
    end

    context "with a Gemfile with a function version" do
      let(:dependency_files) { bundler_project_dependency_files("function_version_gemfile") }
      let(:requirements) do
        [{ file: "Gemfile", requirement: "1.0.0", groups: [], source: nil }]
      end

      it { is_expected.to eq(false) }
    end
  end
end
