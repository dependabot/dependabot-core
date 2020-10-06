# frozen_string_literal: true

require "spec_helper"
require "shared_contexts"

require "dependabot/dependency"
require_relative "../../../helpers/lib/functions/version_resolver"

RSpec.describe Functions::VersionResolver do
  let(:version_resolver) do
    described_class.new(
      dependency_name: dependency_name,
      dependency_requirements: [],
      gemfile_name: gemfile_name,
      lockfile_name: lockfile_name,
      using_bundler_2: false,
      dir: fixture_directory,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end

  let(:fixture_directory) do
    File.join(
      File.dirname(__FILE__), "..", "..", "fixtures", "ruby", "gemfiles"
    )
  end
  let(:gemfile_name) do
    File.join(fixture_directory, gemfile_fixture_name)
  end
  let(:lockfile_name) do
    File.join(fixture_directory, lockfile_fixture_name)
  end

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
  let(:rubygems_url) { "https://index.rubygems.org/api/v1/" }

  include_context "stub rubygems compact index"

  describe "#version_details" do
    subject { version_resolver.version_details }

    include_context "stub rubygems compact index"

    context "with a private gemserver source" do
      let(:gemfile_fixture_name) { "specified_source" }
      let(:lockfile_fixture_name) { "specified_source.lock" }
      let(:requirement_string) { ">= 0" }

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
  end

  context "with a legacy Ruby which disallows the latest version" do
    subject { version_resolver.version_details }

    let(:gemfile_fixture_name) { "legacy_ruby" }
    let(:lockfile_fixture_name) { "legacy_ruby.lock" }
    let(:dependency_name) { "public_suffix" }
    let(:requirement_string) { ">= 0" }

    # The latest version of public_suffix is 2.0.5, but requires Ruby 2.0.0
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
            body: fixture("ruby",
                          "rubygems_responses",
                          "dependencies-public_suffix")
          )

        stub_request(:get, rubygems_url + "versions/public_suffix.json").
          to_return(status: 200, body: rubygems_versions)
      end
      let(:rubygems_versions) do
        fixture("ruby", "rubygems_responses", "versions-public_suffix.json")
      end

      it { is_expected.to be_nil }

      context "and the dependency doesn't have a required Ruby version" do
        let(:rubygems_versions) do
          fixture(
            "ruby",
            "rubygems_responses",
            "versions-public_suffix.json"
          ).gsub(/"ruby_version": .*,/, '"ruby_version": null,')
        end

        it([:version]) { is_expected.to eq(Gem::Version.new("3.0.2")) }
      end
    end
  end
end
