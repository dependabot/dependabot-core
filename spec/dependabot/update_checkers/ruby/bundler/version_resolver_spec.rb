# frozen_string_literal: true

require "spec_helper"
require "shared_contexts"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/ruby/bundler/version_resolver"
require "bundler/compact_index_client"

RSpec.describe Dependabot::UpdateCheckers::Ruby::Bundler::VersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      ignored_versions: ignored_versions,
      credentials: [
        {
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      ]
    )
  end
  let(:dependency_files) { [gemfile, lockfile] }
  let(:ignored_versions) { [] }

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
    [
      {
        file: "Gemfile",
        requirement: requirement_string,
        groups: [],
        source: source
      }
    ]
  end
  let(:source) { nil }
  let(:requirement_string) { ">= 0" }

  let(:gemfile) do
    Dependabot::DependencyFile.new(
      content: fixture("ruby", "gemfiles", gemfile_fixture_name),
      name: "Gemfile"
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      content: fixture("ruby", "lockfiles", lockfile_fixture_name),
      name: "Gemfile.lock"
    )
  end
  let(:gemspec) do
    Dependabot::DependencyFile.new(
      content: fixture("ruby", "gemspecs", gemspec_fixture_name),
      name: "example.gemspec"
    )
  end
  let(:gemfile_fixture_name) { "Gemfile" }
  let(:lockfile_fixture_name) { "Gemfile.lock" }
  let(:gemspec_fixture_name) { "example" }
  let(:rubygems_url) { "https://rubygems.org/api/v1/" }

  describe "#latest_version_details" do
    subject { resolver.latest_version_details }

    context "with a rubygems source" do
      before do
        rubygems_response = fixture("ruby", "rubygems_response_versions.json")
        stub_request(:get, rubygems_url + "versions/business.json").
          to_return(status: 200, body: rubygems_response)
      end

      its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }

      it "only hits Rubygems once" do
        resolver.latest_version_details
        resolver.latest_version_details
        expect(WebMock).
          to have_requested(:get, rubygems_url + "versions/business.json").once
      end

      context "when the gem isn't on Rubygems" do
        before do
          stub_request(:get, rubygems_url + "versions/business.json").
            to_return(status: 404, body: "This rubygem could not be found.")
        end

        it { is_expected.to be_nil }
      end

      context "when the user is ignoring the latest version" do
        let(:ignored_versions) { [">= 1.5.0.a, < 1.6"] }
        its([:version]) { is_expected.to eq(Gem::Version.new("1.4.0")) }
      end

      context "with a prerelease version specified" do
        let(:gemfile_fixture_name) { "prerelease_specified" }
        let(:requirement_string) { "~> 1.4.0.rc1" }

        before do
          rubygems_response = fixture("ruby", "rubygems_response_versions.json")
          stub_request(:get, rubygems_url + "versions/business.json").
            to_return(status: 200, body: rubygems_response)
        end
        its([:version]) { is_expected.to eq(Gem::Version.new("1.6.0.beta")) }
      end

      context "with a Ruby version specified" do
        let(:gemfile_fixture_name) { "explicit_ruby" }
        its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }
      end

      context "given a Gemfile that loads a .ruby-version file" do
        let(:gemfile_fixture_name) { "ruby_version_file" }
        let(:ruby_version_file) do
          Dependabot::DependencyFile.new content: "2.2.0", name: ".ruby-version"
        end
        let(:dependency_files) { [gemfile, lockfile, ruby_version_file] }

        its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }
      end

      context "with a gemspec and a Gemfile" do
        let(:dependency_files) { [gemfile, gemspec] }
        let(:gemspec_fixture_name) { "small_example" }
        let(:gemfile_fixture_name) { "imports_gemspec" }

        its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }

        context "with a dependency that only appears in the gemspec" do
          let(:gemspec_fixture_name) { "example" }
          let(:dependency_name) { "octokit" }

          before do
            response = fixture("ruby", "rubygems_response_versions.json")
            stub_request(:get, rubygems_url + "versions/octokit.json").
              to_return(status: 200, body: response)
          end

          its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }
        end
      end

      context "with only a gemspec" do
        let(:dependency_files) { [gemspec] }
        let(:gemspec_fixture_name) { "small_example" }

        its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }
      end

      context "with only a Gemfile" do
        let(:dependency_files) { [gemfile] }
        let(:gemfile_fixture_name) { "Gemfile" }

        its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }
      end
    end

    context "with a private rubygems source" do
      let(:gemfile_fixture_name) { "specified_source" }
      let(:lockfile_fixture_name) { "specified_source.lock" }
      let(:source) { { type: "rubygems" } }
      let(:registry_url) { "https://repo.fury.io/greysteil/" }
      let(:gemfury_business_url) do
        "https://repo.fury.io/greysteil/api/v1/dependencies?gems=business"
      end

      before do
        stub_request(:get, registry_url + "versions").
          with(basic_auth: ["SECRET_CODES", ""]).
          to_return(status: 404)
        stub_request(:get, registry_url + "api/v1/dependencies").
          with(basic_auth: ["SECRET_CODES", ""]).
          to_return(status: 200)
        stub_request(:get, gemfury_business_url).
          with(basic_auth: ["SECRET_CODES", ""]).
          to_return(status: 200, body: fixture("ruby", "gemfury_response"))
      end

      its([:version]) { is_expected.to eq(Gem::Version.new("1.9.0")) }

      context "when the user is ignoring the latest version" do
        let(:ignored_versions) { [">= 1.9.0.a, < 2.0"] }
        its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }
      end

      context "that we don't have authentication details for" do
        before do
          stub_request(:get, registry_url + "versions").
            with(basic_auth: ["SECRET_CODES", ""]).
            to_return(status: 401)
          stub_request(:get, registry_url + "api/v1/dependencies").
            with(basic_auth: ["SECRET_CODES", ""]).
            to_return(status: 401)
          stub_request(:get, registry_url + "specs.4.8.gz").
            with(basic_auth: ["SECRET_CODES", ""]).
            to_return(status: 401)
        end

        it "blows up with a useful error" do
          expect { resolver.latest_version_details }.
            to raise_error do |error|
              expect(error).to be_a(Dependabot::PrivateSourceNotReachable)
              expect(error.source).to eq("repo.fury.io")
            end
        end
      end

      context "that we have bad authentication details for" do
        before do
          stub_request(:get, registry_url + "versions").
            with(basic_auth: ["SECRET_CODES", ""]).
            to_return(status: 403)
          stub_request(:get, registry_url + "api/v1/dependencies").
            with(basic_auth: ["SECRET_CODES", ""]).
            to_return(status: 403)
          stub_request(:get, registry_url + "specs.4.8.gz").
            with(basic_auth: ["SECRET_CODES", ""]).
            to_return(status: 403)
        end

        it "blows up with a useful error" do
          expect { resolver.latest_version_details }.
            to raise_error do |error|
              expect(error).to be_a(Dependabot::PrivateSourceNotReachable)
              expect(error.source).
                to eq("https://SECRET_CODES@repo.fury.io/greysteil/")
            end
        end
      end

      context "that bad-requested, but was a private repo" do
        before do
          stub_request(:get, registry_url + "versions").
            with(basic_auth: ["SECRET_CODES", ""]).
            to_return(status: 400)
          stub_request(:get, registry_url + "api/v1/dependencies").
            with(basic_auth: ["SECRET_CODES", ""]).
            to_return(status: 400)
          stub_request(:get, registry_url + "specs.4.8.gz").
            with(basic_auth: ["SECRET_CODES", ""]).
            to_return(status: 400)
        end

        it "blows up with a useful error" do
          expect { resolver.latest_version_details }.
            to raise_error do |error|
              expect(error).to be_a(Dependabot::PrivateSourceNotReachable)
              expect(error.source).
                to eq("https://repo.fury.io/greysteil/")
            end
        end
      end

      context "that doesn't have details of the gem" do
        before do
          stub_request(:get, gemfury_business_url).
            with(basic_auth: ["SECRET_CODES", ""]).
            to_return(status: 404)

          # Stub indexes to return details of other gems (but not this one)
          stub_request(:get, registry_url + "specs.4.8.gz").
            to_return(
              status: 200,
              body: fixture("ruby", "contribsys_old_index_response")
            )
          stub_request(:get, registry_url + "prerelease_specs.4.8.gz").
            to_return(
              status: 200,
              body: fixture("ruby", "contribsys_old_index_prerelease_response")
            )
        end

        it { is_expected.to be_nil }
      end

      context "that only implements the old Bundler index format..." do
        let(:gemfile_fixture_name) { "sidekiq_pro" }
        let(:lockfile_fixture_name) { "sidekiq_pro.lock" }
        let(:dependency_name) { "sidekiq-pro" }
        let(:registry_url) { "https://gems.contribsys.com/" }
        before do
          stub_request(:get, registry_url + "versions").
            with(basic_auth: %w(username password)).
            to_return(status: 404)
          stub_request(:get, registry_url + "api/v1/dependencies").
            with(basic_auth: %w(username password)).
            to_return(status: 404)
          stub_request(:get, registry_url + "specs.4.8.gz").
            with(basic_auth: %w(username password)).
            to_return(
              status: 200,
              body: fixture("ruby", "contribsys_old_index_response")
            )
          stub_request(:get, registry_url + "prerelease_specs.4.8.gz").
            with(basic_auth: %w(username password)).
            to_return(
              status: 200,
              body: fixture("ruby", "contribsys_old_index_prerelease_response")
            )
        end

        its([:version]) { is_expected.to eq(Gem::Version.new("3.5.2")) }
      end
    end

    context "given a git source" do
      let(:gemfile_fixture_name) { "git_source" }
      let(:lockfile_fixture_name) { "git_source.lock" }

      before do
        rubygems_response = fixture("ruby", "rubygems_response_versions.json")
        stub_request(:get, rubygems_url + "versions/business.json").
          to_return(status: 200, body: rubygems_response)
      end

      context "that is the gem we're checking for" do
        let(:dependency_name) { "business" }
        let(:current_version) { "a1b78a929dac93a52f08db4f2847d76d6cfe39bd" }
        let(:source) do
          {
            type: "git",
            url: "https://github.com/gocardless/business",
            branch: "master",
            ref: "a1b78a9" # Pinned, to ensure we unpin
          }
        end

        it "fetches the latest SHA-1 hash" do
          commit_sha = resolver.latest_version_details[:commit_sha]
          expect(commit_sha).to match(/^[0-9a-f]{40}$/)
          expect(commit_sha).to_not eq(current_version)
        end

        context "when the gem has a bad branch" do
          let(:gemfile_fixture_name) { "bad_branch_business" }
          let(:lockfile_fixture_name) { "bad_branch_business.lock" }
          let(:source) do
            {
              type: "git",
              url: "https://github.com/gocardless/business",
              branch: "bad_branch",
              ref: "bad_branch"
            }
          end
          around { |example| capture_stderr { example.run } }

          it "raises a helpful error" do
            expect { resolver.latest_version_details }.
              to raise_error do |error|
                expect(error).to be_a Dependabot::GitDependencyReferenceNotFound
                expect(error.dependency).to eq("business")
              end
          end
        end
      end

      context "that is not the gem we're checking" do
        let(:gemfile_fixture_name) { "git_source" }
        let(:lockfile_fixture_name) { "git_source.lock" }
        let(:dependency_name) { "statesman" }

        before do
          stub_request(:get, rubygems_url + "versions/statesman.json").
            to_return(
              status: 200,
              body: fixture("ruby", "rubygems_response_versions.json")
            )
        end

        its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }

        context "that is private" do
          let(:gemfile_fixture_name) { "private_git_source" }
          let(:lockfile_fixture_name) { "private_git_source.lock" }

          its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }
        end
      end
    end

    context "given a path source" do
      let(:gemfile_fixture_name) { "path_source" }
      let(:lockfile_fixture_name) { "path_source.lock" }

      before do
        rubygems_response = fixture("ruby", "rubygems_response_versions.json")
        stub_request(:get, rubygems_url + "versions/business.json").
          to_return(status: 200, body: rubygems_response)
      end

      context "with a downloaded gemspec" do
        let(:dependency_files) { [gemfile, lockfile, gemspec] }
        let(:gemspec_fixture_name) { "example" }
        let(:gemspec) do
          Dependabot::DependencyFile.new(
            content: fixture("ruby", "gemspecs", gemspec_fixture_name),
            name: "plugins/example/example.gemspec"
          )
        end

        context "that is not the gem we're checking" do
          its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }
        end

        context "that is the gem we're checking" do
          let(:dependency_name) { "example" }
          let(:source) { { type: "path" } }

          it { is_expected.to be_nil }
        end
      end
    end
  end

  describe "#latest_resolvable_version_details" do
    subject { resolver.latest_resolvable_version_details }

    include_context "stub rubygems"

    context "with a rubygems source" do
      context "with a ~> version specified constraining the update" do
        let(:gemfile_fixture_name) { "Gemfile" }
        let(:lockfile_fixture_name) { "Gemfile.lock" }

        its([:version]) { is_expected.to eq(Gem::Version.new("1.4.0")) }
      end

      context "with a minor version specified that can update" do
        let(:gemfile_fixture_name) { "minor_version_specified" }
        let(:lockfile_fixture_name) { "Gemfile.lock" }

        its([:version]) { is_expected.to eq(Gem::Version.new("1.8.0")) }
      end

      context "that only appears in the lockfile" do
        let(:gemfile_fixture_name) { "subdependency" }
        let(:lockfile_fixture_name) { "subdependency.lock" }
        let(:dependency_name) { "i18n" }

        its([:version]) { is_expected.to eq(Gem::Version.new("0.7.0")) }
      end

      context "with a Bundler version specified" do
        let(:gemfile_fixture_name) { "bundler_specified" }
        let(:lockfile_fixture_name) { "bundler_specified.lock" }

        its([:version]) { is_expected.to eq(Gem::Version.new("1.4.0")) }
      end

      context "with a version conflict at the latest version" do
        let(:gemfile_fixture_name) { "version_conflict_no_req_change" }
        let(:lockfile_fixture_name) { "version_conflict_no_req_change.lock" }
        let(:dependency_name) { "ibandit" }

        # The latest version of ibandit is 0.8.5, but 0.3.4 is the latest
        # version compatible with the version of i18n in the Gemfile.
        its([:version]) { is_expected.to eq(Gem::Version.new("0.3.4")) }
      end

      context "with a legacy Ruby which disallows the latest version" do
        let(:gemfile_fixture_name) { "legacy_ruby" }
        let(:lockfile_fixture_name) { "legacy_ruby.lock" }
        let(:dependency_name) { "public_suffix" }

        # The latest version of public_suffic is 2.0.5, but requires Ruby 2.0.0
        # or greater.
        its([:version]) { is_expected.to eq(Gem::Version.new("1.4.6")) }

        context "when Bundler's compact index is down" do
          before do
            old_index_url = "https://index.rubygems.org/api/v1/dependencies"
            stub_request(:get, "https://index.rubygems.org/versions").
              to_return(status: 500, body: "We'll be back soon")
            stub_request(:get, "https://index.rubygems.org/info/public_suffix").
              to_return(status: 500, body: "We'll be back soon")
            stub_request(:get, old_index_url).to_return(status: 200)
            stub_request(:get, old_index_url + "?gems=public_suffix").
              to_return(
                status: 200,
                body: fixture("ruby", "rubygems-dependencies-public_suffix")
              )

            stub_request(:get, rubygems_url + "versions/public_suffix.json").
              to_return(status: 200, body: rubygems_versions)
          end
          let(:rubygems_versions) do
            fixture("ruby", "rubygems-versions-public_suffix.json")
          end

          it { is_expected.to be_nil }

          context "and the dependency doesn't have a required Ruby version" do
            let(:rubygems_versions) do
              fixture("ruby", "rubygems-versions-public_suffix.json").gsub(
                /"ruby_version": .*,/,
                '"ruby_version": null,'
              )
            end

            its([:version]) { is_expected.to eq(Gem::Version.new("3.0.2")) }
          end
        end
      end

      context "with JRuby" do
        let(:gemfile_fixture_name) { "jruby" }
        let(:lockfile_fixture_name) { "jruby.lock" }
        let(:dependency_name) { "json" }

        its([:version]) { is_expected.to be >= Gem::Version.new("1.4.6") }
      end

      context "when a gem has been yanked" do
        let(:gemfile_fixture_name) { "minor_version_specified" }
        let(:lockfile_fixture_name) { "yanked_gem.lock" }

        context "and it's that gem that we're attempting to bump" do
          its([:version]) { is_expected.to eq(Gem::Version.new("1.8.0")) }
        end

        context "and it's another gem" do
          let(:dependency_name) { "statesman" }
          its([:version]) { is_expected.to eq(Gem::Version.new("1.3.1")) }
        end
      end
    end

    context "with a private gemserver source" do
      let(:gemfile_fixture_name) { "specified_source" }
      let(:lockfile_fixture_name) { "specified_source.lock" }

      before do
        gemfury_url = "https://repo.fury.io/greysteil/"
        gemfury_deps_url = gemfury_url + "api/v1/dependencies"

        stub_request(:get, gemfury_url + "versions").
          to_return(status: 200, body: fixture("ruby", "gemfury-index"))
        stub_request(:get, gemfury_url + "info/business").to_return(status: 404)
        stub_request(:get, gemfury_deps_url).to_return(status: 200)
        stub_request(:get, gemfury_deps_url + "?gems=business,statesman").
          to_return(status: 200, body: fixture("ruby", "gemfury_response"))
        stub_request(:get, gemfury_deps_url + "?gems=business").
          to_return(status: 200, body: fixture("ruby", "gemfury_response"))
        stub_request(:get, gemfury_deps_url + "?gems=statesman").
          to_return(status: 200, body: fixture("ruby", "gemfury_response"))
      end

      its([:version]) { is_expected.to eq(Gem::Version.new("1.9.0")) }
    end

    context "when the Gem can't be found" do
      let(:gemfile_fixture_name) { "unavailable_gem" }

      it "raises a DependencyFileNotResolvable error" do
        expect { subject }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "given an unreadable Gemfile" do
      let(:gemfile_fixture_name) { "includes_requires" }

      it "raises a useful error" do
        expect { subject }.
          to raise_error(Dependabot::DependencyFileNotEvaluatable) do |error|
            # Test that the temporary path isn't included in the error message
            expect(error.message).to_not include("dependabot_20")
          end
      end
    end

    context "given a path source" do
      let(:gemfile_fixture_name) { "path_source" }
      let(:lockfile_fixture_name) { "path_source.lock" }

      context "without a downloaded gemspec" do
        let(:dependency_files) { [gemfile, lockfile] }

        it "raises a PathDependenciesNotReachable error" do
          expect { subject }.
            to raise_error(Dependabot::PathDependenciesNotReachable)
        end
      end
    end
  end
end
