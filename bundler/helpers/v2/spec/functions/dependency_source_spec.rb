# typed: false
# frozen_string_literal: true

require "native_spec_helper"
require "shared_contexts"

RSpec.describe Functions::DependencySource do
  include_context "when in a temporary bundler directory"

  let(:dependency_source) do
    described_class.new(
      gemfile_name: "Gemfile",
      dependency_name: dependency_name
    )
  end

  let(:dependency_name) { "business" }

  let(:project_name) { "specified_source_no_lockfile" }
  let(:registry_url) { "https://repo.fury.io/greysteil/" }
  let(:gemfury_business_url) do
    "https://repo.fury.io/greysteil/api/v1/dependencies?gems=business"
  end

  before do
    stub_request(:get, registry_url + "versions")
      .with(basic_auth: ["SECRET_CODES", ""])
      .to_return(status: 404)
    stub_request(:get, registry_url + "api/v1/dependencies")
      .with(basic_auth: ["SECRET_CODES", ""])
      .to_return(status: 200)
    stub_request(:get, gemfury_business_url)
      .with(basic_auth: ["SECRET_CODES", ""])
      .to_return(status: 200, body: fixture("ruby", "gemfury_response"))
  end

  describe "#private_registry_versions" do
    subject(:private_registry_versions) do
      in_tmp_folder { dependency_source.private_registry_versions }
    end

    it "returns all versions from the private source" do
      expect(private_registry_versions).to eq([
        Gem::Version.new("1.5.0"),
        Gem::Version.new("1.9.0"),
        Gem::Version.new("1.10.0.beta")
      ])
    end

    context "when specified as the default source" do
      let(:project_name) { "specified_default_source_no_lockfile" }

      it "returns all versions from the private source" do
        expect(private_registry_versions).to eq([
          Gem::Version.new("1.5.0"),
          Gem::Version.new("1.9.0"),
          Gem::Version.new("1.10.0.beta")
        ])
      end
    end

    context "when we don't have authentication details" do
      before do
        stub_request(:get, registry_url + "versions")
          .with(basic_auth: ["SECRET_CODES", ""])
          .to_return(status: 401)
        stub_request(:get, registry_url + "api/v1/dependencies")
          .with(basic_auth: ["SECRET_CODES", ""])
          .to_return(status: 401)
        stub_request(:get, registry_url + "specs.4.8.gz")
          .with(basic_auth: ["SECRET_CODES", ""])
          .to_return(status: 401)
      end

      it "blows up with a useful error" do
        error_class = Bundler::Fetcher::BadAuthenticationError
        expect { private_registry_versions }
          .to raise_error do |error|
            expect(error).to be_a(error_class)
            expect(error.message).to include("Bad username or password for")
          end
      end
    end

    context "when we have bad authentication details" do
      before do
        stub_request(:get, registry_url + "versions")
          .with(basic_auth: ["SECRET_CODES", ""])
          .to_return(status: 403)
        stub_request(:get, registry_url + "api/v1/dependencies")
          .with(basic_auth: ["SECRET_CODES", ""])
          .to_return(status: 403)
        stub_request(:get, registry_url + "specs.4.8.gz")
          .with(basic_auth: ["SECRET_CODES", ""])
          .to_return(status: 403)
      end

      it "blows up with a useful error" do
        error_class = Bundler::Fetcher::AuthenticationForbiddenError
        expect { private_registry_versions }
          .to raise_error do |error|
            expect(error).to be_a(error_class)
            expect(error.message).to include("Access token could not be authenticated for")
          end
      end
    end

    context "when there is a bad request but it's a private repo" do
      before do
        stub_request(:get, registry_url + "versions")
          .with(basic_auth: ["SECRET_CODES", ""])
          .to_return(status: 400)
        stub_request(:get, registry_url + "api/v1/dependencies")
          .with(basic_auth: ["SECRET_CODES", ""])
          .to_return(status: 400)
        stub_request(:get, registry_url + "specs.4.8.gz")
          .with(basic_auth: ["SECRET_CODES", ""])
          .to_return(status: 400)
        stub_request(:get, registry_url + "info/business")
          .with(basic_auth: ["SECRET_CODES", ""])
          .to_return(status: 400)
      end

      it "blows up with a useful error" do
        expect { private_registry_versions }
          .to raise_error do |error|
            expect(error).to be_a(Bundler::HTTPError)
            expect(error.message)
              .to include("Could not fetch specs from #{registry_url} due to underlying error")
          end
      end
    end

    context "when the gem details are not available" do
      before do
        stub_request(:get, gemfury_business_url)
          .with(basic_auth: ["SECRET_CODES", ""])
          .to_return(status: 404)

        # Stub indexes to return details of other gems (but not this one)
        stub_request(:get, registry_url + "specs.4.8.gz")
          .to_return(
            status: 200,
            body: fixture("ruby", "contribsys_old_index_response")
          )
        stub_request(:get, registry_url + "prerelease_specs.4.8.gz")
          .to_return(
            status: 200,
            body: fixture("ruby", "contribsys_old_index_prerelease_response")
          )
      end

      it { is_expected.to be_empty }
    end

    context "when only the old Bundler index format is implemented" do
      let(:project_name) { "sidekiq_pro" }
      let(:dependency_name) { "sidekiq-pro" }
      let(:registry_url) { "https://gems.contribsys.com/" }

      before do
        stub_request(:get, registry_url + "versions")
          .with(basic_auth: %w(username password))
          .to_return(status: 404)
        stub_request(:get, registry_url + "api/v1/dependencies")
          .with(basic_auth: %w(username password))
          .to_return(status: 404)
        stub_request(:get, registry_url + "specs.4.8.gz")
          .with(basic_auth: %w(username password))
          .to_return(
            status: 200,
            body: fixture("ruby", "contribsys_old_index_response")
          )
        stub_request(:get, registry_url + "prerelease_specs.4.8.gz")
          .with(basic_auth: %w(username password))
          .to_return(
            status: 200,
            body: fixture("ruby", "contribsys_old_index_prerelease_response")
          )
      end

      it "returns all versions from the private source" do
        expect(private_registry_versions.length).to be(70)
        expect(private_registry_versions.min).to eql(Gem::Version.new("1.0.0"))
        expect(private_registry_versions.max).to eql(Gem::Version.new("3.5.2"))
      end
    end
  end
end
