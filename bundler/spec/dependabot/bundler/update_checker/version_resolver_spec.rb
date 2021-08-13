# frozen_string_literal: true

require "spec_helper"
require "shared_contexts"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bundler/update_checker/version_resolver"

RSpec.describe Dependabot::Bundler::UpdateChecker::VersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      unprepared_dependency_files: dependency_files,
      ignored_versions: ignored_versions,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }],
      unlock_requirement: unlock_requirement,
      latest_allowable_version: latest_allowable_version,
      options: {}
    )
  end
  let(:ignored_versions) { [] }
  let(:latest_allowable_version) { nil }
  let(:unlock_requirement) { false }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: current_version,
      requirements: requirements,
      package_manager: "bundler"
    )
  end
  let(:dependency_name) { "business" }
  let(:current_version) { "1.3" }
  let(:requirements) do
    [{
      file: "Gemfile",
      requirement: requirement_string,
      groups: [],
      source: source
    }]
  end
  let(:source) { nil }
  let(:requirement_string) { ">= 0" }
  let(:rubygems_url) { "https://index.rubygems.org/api/v1/" }

  describe "#latest_resolvable_version_details" do
    subject { resolver.latest_resolvable_version_details }

    context "with a rubygems source" do
      context "with a ~> version specified constraining the update" do
        let(:requirement_string) { "~> 1.4.0" }

        let(:dependency_files) { bundler_project_dependency_files("gemfile") }
        its([:version]) { is_expected.to eq(Gem::Version.new("1.4.0")) }
      end

      context "with a minor version specified that can update" do
        let(:requirement_string) { "~> 1.4" }

        let(:dependency_files) { bundler_project_dependency_files("minor_version_specified_gemfile") }
        its([:version]) { is_expected.to eq(Gem::Version.new("1.18.0")) }
      end

      context "when updating a dep blocked by a sub-dep" do
        let(:dependency_name) { "dummy-pkg-a" }
        let(:current_version) { "1.0.1" }
        let(:requirements) do
          [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
        end

        let(:dependency_files) { bundler_project_dependency_files("blocked_by_subdep") }
        its([:version]) { is_expected.to eq(Gem::Version.new("1.1.0")) }
      end

      context "that only appears in the lockfile" do
        let(:dependency_name) { "i18n" }
        let(:requirements) { [] }

        let(:dependency_files) { bundler_project_dependency_files("subdependency") }
        its([:version]) { is_expected.to eq(Gem::Version.new("0.7.0")) }

        # TODO: https://github.com/dependabot/dependabot-core/issues/2364
        # context "that will be removed if other sub-dependencies are updated" do
        #   let(:gemfile_fixture_name) { "subdependency_change" }
        #   let(:lockfile_fixture_name) { "subdependency_change.lock" }
        #   let(:dependency_name) { "nokogiri" }
        #   let(:requirements) { [] }

        #   pending "is updated" do
        #     expect(subject.version).to eq(Gem::Version.new("1.10.9"))
        #   end
        # end
      end

      context "with a Bundler v1 version specified", :bundler_v1_only do
        let(:requirement_string) { "~> 1.4.0" }

        let(:dependency_files) { bundler_project_dependency_files("bundler_specified") }
        its([:version]) { is_expected.to eq(Gem::Version.new("1.4.0")) }

        context "attempting to update Bundler" do
          let(:dependency_name) { "bundler" }
          include_context "stub rubygems versions api"

          let(:dependency_files) { bundler_project_dependency_files("bundler_specified") }
          its([:version]) { is_expected.to eq(Gem::Version.new("1.16.3")) }

          context "when wrapped in a source block" do
            let(:dependency_files) do
              bundler_project_dependency_files("bundler_specified_in_source_bundler_specified")
            end
            its([:version]) { is_expected.to eq(Gem::Version.new("1.16.3")) }
          end

          # TODO: https://github.com/dependabot/dependabot-core/issues/2364
          # context "and required by another dependency" do
          #   let(:gemfile_fixture_name) { "bundler_specified_and_required" }
          #   let(:lockfile_fixture_name) do
          #     "bundler_specified_and_required.lock"
          #   end

          #   pending { is_expected.to be_nil }
          # end
        end
      end

      context "with a Bundler v2 version specified", :bundler_v2_only do
        let(:requirement_string) { "~> 1.4.0" }

        let(:dependency_files) { bundler_project_dependency_files("bundler_specified") }
        its([:version]) { is_expected.to eq(Gem::Version.new("1.4.0")) }

        context "attempting to update Bundler" do
          let(:dependency_name) { "bundler" }
          let(:requirement_string) { "~> 2.2.0" }

          let(:dependency_files) { bundler_project_dependency_files("bundler_specified") }

          before do
            stub_request(:get, rubygems_url + "versions/bundler.json").
              to_return(status: 200, body: fixture("rubygems_responses", "versions-bundler.json"))
          end

          it "returns nil as resolution returns the bundler version installed by core" do
            expect(subject).to be_nil
          end
        end
      end

      context "with a dependency that requiers bundler v1", :bundler_v1_only do
        let(:dependency_name) { "guard-bundler" }
        let(:requirement_string) { "2.2.1" }

        let(:dependency_files) { bundler_project_dependency_files("requires_bundler") }
        its([:version]) { is_expected.to eq(Gem::Version.new("2.2.1")) }
      end

      context "when bundled with v1 and requesting a version that requires bundler v2", :bundler_v1_only do
        let(:dependency_name) { "guard-bundler" }
        let(:requirement_string) { "~> 3.0.0" }

        let(:dependency_files) { bundler_project_dependency_files("requires_bundler") }

        it "raises a DependencyFileNotResolvable error" do
          expect { subject }.
            to raise_error(Dependabot::DependencyFileNotResolvable)
        end
      end

      context "with a dependency that requiers bundler v2", :bundler_v2_only do
        let(:dependency_name) { "guard-bundler" }
        let(:requirement_string) { "3.0.0" }

        let(:dependency_files) { bundler_project_dependency_files("requires_bundler") }

        pending "resolves version" do
          expect(subject.version).to eq(Gem::Version.new("3.0.0"))
        end
      end

      context "when bundled with v2 and requesting a version that requires bundler v1", :bundler_v2_only do
        let(:dependency_name) { "guard-bundler" }
        let(:requirement_string) { "~> 2.2.0" }

        let(:dependency_files) { bundler_project_dependency_files("requires_bundler") }

        pending "raises a DependencyFileNotResolvable error" do
          expect { subject }.
            to raise_error(Dependabot::DependencyFileNotResolvable)
        end
      end

      context "with a default gem specified" do
        let(:requirement_string) { "~> 1.4" }

        let(:dependency_files) { bundler_project_dependency_files("default_gem_specified") }
        its([:version]) { is_expected.to eq(Gem::Version.new("1.18.0")) }
      end

      context "with a version conflict at the latest version" do
        let(:dependency_name) { "ibandit" }
        let(:requirement_string) { "~> 0.1" }

        # The latest version of ibandit is 0.8.5, but 0.11.28 is the latest
        # version compatible with the version of i18n in the Gemfile.lock.
        let(:dependency_files) { bundler_project_dependency_files("version_conflict_no_req_change") }
        its([:version]) { is_expected.to eq(Gem::Version.new("0.11.28")) }

        context "with a gems.rb and gems.locked" do
          let(:requirements) do
            [{
              file: "gems.rb",
              requirement: requirement_string,
              groups: [],
              source: source
            }]
          end

          let(:dependency_files) { bundler_project_dependency_files("version_conflict_no_req_change_gems_rb") }
          its([:version]) { is_expected.to eq(Gem::Version.new("0.11.28")) }
        end
      end

      context "with no update possible due to a version conflict" do
        let(:dependency_name) { "rspec-mocks" }
        let(:requirement_string) { ">= 0" }

        let(:dependency_files) { bundler_project_dependency_files("version_conflict_with_listed_subdep") }
        its([:version]) { is_expected.to eq(Gem::Version.new("3.6.0")) }
      end

      context "with a legacy Ruby which disallows the latest version" do
        let(:dependency_name) { "public_suffix" }
        let(:requirement_string) { ">= 0" }

        # The latest version of public_suffix is 2.0.5, but requires Ruby 2.0.0
        # or greater.
        let(:dependency_files) { bundler_project_dependency_files("legacy_ruby") }
        its([:version]) { is_expected.to eq(Gem::Version.new("1.4.6")) }
      end

      context "with a legacy Ruby when Bundler's compact index is down" do
        let(:dependency_name) { "public_suffix" }
        let(:requirement_string) { ">= 0" }
        let(:dependency_files) { bundler_project_dependency_files("legacy_ruby") }
        let(:versions_url) do
          "https://rubygems.org/api/v1/versions/public_suffix.json"
        end
        let(:rubygems_versions) do
          fixture("rubygems_responses", "versions-public_suffix.json")
        end

        before do
          allow(Dependabot::Bundler::NativeHelpers).
            to receive(:run_bundler_subprocess).
            with({
              bundler_version: PackageManagerHelper.bundler_version,
              function: "resolve_version",
              args: anything
            }).
            and_return(
              {
                version: "3.0.2",
                ruby_version: "1.9.3",
                fetcher: "Bundler::Fetcher::Dependency"
              }
            )

          stub_request(:get, versions_url).
            to_return(status: 200, body: rubygems_versions)
        end

        it { is_expected.to be_nil }

        context "and the dependency doesn't have a required Ruby version" do
          let(:rubygems_versions) do
            fixture(
              "rubygems_responses",
              "versions-public_suffix.json"
            ).gsub(/"ruby_version": .*,/, '"ruby_version": null,')
          end

          let(:dependency_files) { bundler_project_dependency_files("legacy_ruby") }
          its([:version]) { is_expected.to eq(Gem::Version.new("3.0.2")) }
        end

        context "and the dependency has a required Ruby version range" do
          let(:rubygems_versions) do
            fixture(
              "rubygems_responses",
              "versions-public_suffix.json"
            ).gsub(/"ruby_version": .*,/, '"ruby_version": ">= 2.2, < 4.0",')
          end

          it { is_expected.to be_nil }
        end
      end

      context "with JRuby" do
        let(:dependency_name) { "json" }
        let(:requirement_string) { ">= 0" }

        let(:dependency_files) { bundler_project_dependency_files("jruby") }
        its([:version]) { is_expected.to be >= Gem::Version.new("1.4.6") }
      end

      context "when a gem has been yanked" do
        let(:requirement_string) { "~> 1.4" }

        context "and it's that gem that we're attempting to bump" do
          let(:dependency_files) { bundler_project_dependency_files("minor_version_specified_yanked_gem") }
          its([:version]) { is_expected.to eq(Gem::Version.new("1.18.0")) }
        end

        context "and it's another gem" do
          let(:dependency_name) { "statesman" }
          let(:requirement_string) { "~> 1.2" }
          let(:dependency_files) { bundler_project_dependency_files("minor_version_specified_yanked_gem") }
          its([:version]) { is_expected.to eq(Gem::Version.new("1.3.1")) }
        end
      end

      context "when unlocking a git dependency would cause errors" do
        let(:current_version) { "1.4.0" }

        let(:dependency_files) { bundler_project_dependency_files("git_source_circular") }

        it "unlocks the version" do
          expect(resolver.latest_resolvable_version_details[:version].canonical_segments.first).to eq(2)
        end
      end

      context "with a ruby exec command that fails" do
        let(:dependency_files) { bundler_project_dependency_files("exec_error_no_lockfile") }

        it "raises a DependencyFileNotEvaluatable error" do
          expect { subject }.
            to raise_error(Dependabot::DependencyFileNotEvaluatable)
        end
      end
    end

    context "when the Gem can't be found" do
      let(:dependency_files) { bundler_project_dependency_files("unavailable_gem_gemfile") }
      let(:requirement_string) { "~> 1.4" }

      it "raises a DependencyFileNotResolvable error" do
        expect { subject }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "given an unreadable Gemfile" do
      let(:dependency_files) { bundler_project_dependency_files("includes_requires_gemfile") }

      it "raises a useful error" do
        expect { subject }.
          to raise_error(Dependabot::DependencyFileNotEvaluatable) do |error|
          # Test that the temporary path isn't included in the error message
          expect(error.message).to_not include("dependabot_20")
        end
      end
    end

    context "given a path source" do
      let(:requirement_string) { "~> 1.4.0" }

      context "without a downloaded gemspec" do
        let(:dependency_files) { bundler_project_dependency_files("path_source_not_reachable") }

        it "raises a PathDependenciesNotReachable error" do
          expect { subject }.
            to raise_error(Dependabot::PathDependenciesNotReachable)
        end
      end
    end

    context "given a git source" do
      context "where updating would cause a circular dependency" do
        let(:dependency_files) { bundler_project_dependency_files("git_source_circular") }

        let(:dependency_name) { "rubygems-circular-dependency" }
        let(:current_version) { "3c85f0bd8d6977b4dfda6a12acf93a282c4f5bf1" }
        let(:source) do
          {
            type: "git",
            url: "https://github.com/dependabot-fixtures/"\
            "rubygems-circular-dependency",
            branch: "master",
            ref: "master"
          }
        end

        it { is_expected.to be_nil }
      end
    end

    context "with a gemspec and a Gemfile" do
      let(:dependency_files) { bundler_project_dependency_files("imports_gemspec_small_example_no_lockfile") }
      let(:unlock_requirement) { true }
      let(:current_version) { nil }
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

      it "unlocks the latest version" do
        expect(resolver.latest_resolvable_version_details[:version].canonical_segments.first).to eq(2)
      end

      context "with an upper bound that is lower than the current req" do
        let(:dependency_files) { bundler_project_dependency_files("imports_gemspec_small_example_no_lockfile") }
        let(:latest_allowable_version) { "1.0.0" }
        let(:ignored_versions) { ["> 1.0.0"] }

        it { is_expected.to be_nil }
      end

      # TODO: https://github.com/dependabot/dependabot-core/issues/2364
      # context "with an implicit pre-release requirement" do
      #   let(:gemfile_fixture_name) { "imports_gemspec_implicit_pre" }
      #   let(:gemspec_fixture_name) { "implicit_pre" }
      #   let(:latest_allowable_version) { "6.0.3.1" }

      #   let(:unlock_requirement) { true }
      #   let(:current_version) { nil }
      #   let(:dependency_name) { "activesupport" }
      #   let(:requirements) do
      #     [{
      #       file: "example.gemspec",
      #       requirement: ">= 6.0",
      #       groups: [],
      #       source: nil
      #     }]
      #   end
      #   pending { is_expected.to be_nil }
      # end

      context "when an old required ruby is specified in the gemspec" do
        let(:dependency_files) { bundler_project_dependency_files("imports_gemspec_old_required_ruby_no_lockfile") }
        let(:dependency_name) { "statesman" }
        let(:latest_allowable_version) { "7.2.0" }

        it "takes the minimum ruby version into account" do
          expect(resolver.latest_resolvable_version_details[:version]).
            to eq(Gem::Version.new("2.0.1"))
        end

        context "that isn't satisfied by the dependencies", :bundler_v2_only do
          let(:dependency_files) do
            bundler_project_dependency_files("imports_gemspec_version_clash_old_required_ruby_no_lockfile")
          end
          let(:current_version) { "3.0.1" }

          it "raises a DependencyFileNotResolvable error" do
            expect { subject }.
              to raise_error(Dependabot::DependencyFileNotResolvable)
          end
        end
      end
    end
  end
end
