# typed: false
# frozen_string_literal: true

require "native_spec_helper"
require "shared_contexts"

RSpec.describe Functions::VersionResolver do
  include_context "when in a temporary bundler directory"
  include_context "when stubbing rubygems compact index"

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
  let(:old_index_url) { rubygems_url + "dependencies" }
  let(:gemfury_url) { "https://repo.fury.io/greysteil/" }

  before do
    stub_request(:get, "https://rubygems.org/quick/Marshal.4.8/statesman-1.2.1.gemspec.rz")
      .to_return(status: 200, body: fixture("rubygems_responses", "statesman-1.2.1.gemspec.rz"))

    stub_request(:get, "https://rubygems.org/quick/Marshal.4.8/statesman-1.2.5.gemspec.rz")
      .to_return(status: 200, body: fixture("rubygems_responses", "statesman-1.2.5.gemspec.rz"))

    stub_request(:get, %r{quick/Marshal.4.8/business-.*.gemspec.rz})
      .to_return(status: 200, body: fixture("rubygems_responses", "business-1.0.0.gemspec.rz"))
  end

  describe "#version_details" do
    subject do
      in_tmp_folder { version_resolver.version_details }
    end

    let(:project_name) { "gemfile" }
    let(:requirement_string) { " >= 0" }

    its([:version]) { is_expected.to eq(Gem::Version.new("1.4.0")) }
    its([:fetcher]) { is_expected.to eq("Bundler::Fetcher::CompactIndex") }

    context "with a private gemserver source" do
      include_context "when stubbing rubygems compact index"

      let(:project_name) { "specified_source" }
      let(:requirement_string) { ">= 0" }

      before do
        gemfury_deps_url = gemfury_url + "api/v1/dependencies"

        stub_request(:get, gemfury_url + "versions")
          .to_return(status: 200, body: fixture("ruby", "gemfury-index"))
        stub_request(:get, gemfury_url + "info/business").to_return(status: 404)
        stub_request(:get, gemfury_deps_url).to_return(status: 200)
        stub_request(:get, gemfury_deps_url + "?gems=business,statesman")
          .to_return(status: 200, body: fixture("ruby", "gemfury_response"))
        stub_request(:get, gemfury_deps_url + "?gems=business")
          .to_return(status: 200, body: fixture("ruby", "gemfury_response"))
        stub_request(:get, gemfury_deps_url + "?gems=statesman")
          .to_return(status: 200, body: fixture("ruby", "gemfury_response"))
      end

      its([:version]) { is_expected.to eq(Gem::Version.new("1.9.0")) }
      its([:fetcher]) { is_expected.to eq("Bundler::Fetcher::Dependency") }
    end

    context "with a git source" do
      let(:project_name) { "git_source" }

      its([:version]) { is_expected.to eq(Gem::Version.new("1.6.0")) }
      its([:fetcher]) { is_expected.to be_nil }
    end

    context "when Bundler's compact index is down" do
      before do
        stub_request(:get, "https://index.rubygems.org/versions")
          .to_return(status: 500, body: "We'll be back soon")
        stub_request(:get, "https://index.rubygems.org/info/public_suffix")
          .to_return(status: 500, body: "We'll be back soon")
        stub_request(:get, old_index_url).to_return(status: 200)
        stub_request(:get, old_index_url + "?gems=business,statesman")
          .to_return(
            status: 200,
            body: fixture("rubygems_responses",
                          "dependencies-default-gemfile")
          )
      end

      its([:version]) { is_expected.to eq(Gem::Version.new("1.4.0")) }
      its([:fetcher]) { is_expected.to eq("Bundler::Fetcher::Dependency") }
    end

    context "when there's a version conflict with a subdep also listed as a top level dependency" do
      let(:project_name) { "version_conflict_with_listed_subdep" }
      let(:dependency_name) { "rspec-mocks" }
      let(:requirement_string) { ">= 0" }

      its([:version]) { is_expected.to be > Gem::Version.new("3.6.0") }
    end
  end
end
