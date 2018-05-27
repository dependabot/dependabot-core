# frozen_string_literal: true

require "spec_helper"
require "shared_contexts"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/ruby/bundler/version_resolver"

RSpec.describe Dependabot::UpdateCheckers::Ruby::Bundler::VersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      ignored_versions: ignored_versions,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
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
    [{
      file: "Gemfile",
      requirement: requirement_string,
      groups: [],
      source: source
    }]
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
