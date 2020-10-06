# frozen_string_literal: true

require "spec_helper"
require "shared_contexts"

require "dependabot/dependency"
require_relative "../../../helpers/lib/functions/version_resolver"

RSpec.describe Functions::VersionResolver do
  let(:gemfile_fixture) do
    fixture("ruby", "gemfiles", gemfile_fixture_name)
  end
  let(:lockfile_fixture) do
    fixture("ruby", "lockfiles", lockfile_fixture_name)
  end

  let(:tmp_path) do
    dir = Dir.mktmpdir("native_helper_spec_", "tmp")
    Pathname.new(dir).expand_path
  end

  before do
    File.write(File.join(tmp_path, "Gemfile"), gemfile_fixture)
    File.write(File.join(tmp_path, "Gemfile.lock"), lockfile_fixture)
  end

  let(:version_resolver) do
    described_class.new(
      dependency_name: dependency_name,
      dependency_requirements: dependency_requirements,
      gemfile_name: "Gemfile",
      lockfile_name: "Gemfile.lock"
    )
  end

  let(:dependency_name) { "business" }
  let(:dependency_requirements) do
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
    subject do
      Dir.chdir(tmp_path) do
        version_resolver.version_details
      end
    end

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

    context "with a legacy Ruby which disallows the latest version" do
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

          its([:version]) { is_expected.to eq(Gem::Version.new("3.0.2")) }
        end
      end
    end
  end
end
