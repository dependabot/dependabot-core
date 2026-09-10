# typed: false
# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/python/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Python::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:version) { "1.0" }
  let(:dependency_name) { "luigi" }
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: [{
        file: "requirements.txt",
        requirement: "==#{version}",
        groups: [],
        source: nil
      }],
      package_manager: "pip"
    )
  end

  before do
    stub_request(:get, "https://example.com/status").to_return(
      status: 200,
      body: "Not GHES",
      headers: {}
    )
    stub_request(:get, "https://initd.org/status").to_return(status: 404)
    stub_request(:get, "https://pypi.org/status").to_return(status: 404)
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    let(:pypi_url) { "https://pypi.org/pypi/#{dependency_name}/json" }

    before do
      stub_request(:get, pypi_url).to_return(status: 200, body: pypi_response)
    end

    context "when there is a github link in the pypi response" do
      let(:pypi_response) { fixture("pypi", "pypi_response.json") }

      it { is_expected.to eq("https://github.com/spotify/luigi") }

      it "caches the call to pypi" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, pypi_url).once
      end
    end

    context "with a private index" do
      let(:credentials) do
        [Dependabot::Credential.new(
          {
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }
        ), Dependabot::Credential.new(
          {
            "type" => "python_index",
            "index-url" => "https://username:password@pypi.posrip.com/pypi/"
          }
        )]
      end
      let(:pypi_response) { fixture("pypi", "pypi_response.json") }

      before do
        private_url = "https://pypi.posrip.com/pypi/#{dependency_name}/json"
        stub_request(:get, pypi_url).to_return(status: 404, body: "")
        stub_request(:get, private_url)
          .with(basic_auth: %w(username password))
          .to_return(status: 200, body: pypi_response)
      end

      it { is_expected.to eq("https://github.com/spotify/luigi") }

      it "still includes public PyPI as a fallback" do
        possible_urls = finder.send(:possible_listing_urls)
        expect(possible_urls).to include(a_string_matching(/pypi\.org/))
      end

      context "with the creds passed as a token" do
        let(:credentials) do
          [Dependabot::Credential.new(
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }
          ), Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://pypi.posrip.com/pypi/",
              "token" => "username:password"
            }
          )]
        end

        it { is_expected.to eq("https://github.com/spotify/luigi") }
      end

      context "with the creds using an email address and basic auth" do
        let(:credentials) do
          [Dependabot::Credential.new(
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }
          ), Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://user@mail.co:password@pypi.posrip.com/pypi/"
            }
          )]
        end

        before do
          private_url = "https://pypi.posrip.com/pypi/#{dependency_name}/json"
          stub_request(:get, private_url)
            .with(basic_auth: %w(user@mail.co password))
            .to_return(status: 200, body: pypi_response)
        end

        it { is_expected.to eq("https://github.com/spotify/luigi") }
      end

      context "when isn't used" do
        before do
          private_url = "https://pypi.posrip.com/pypi/#{dependency_name}/json"
          stub_request(:get, private_url).to_return(status: 404, body: "")
          stub_request(:get, pypi_url)
            .to_return(status: 200, body: pypi_response)
        end

        it { is_expected.to eq("https://github.com/spotify/luigi") }

        context "when it doesn't return json" do
          before do
            private_url = "https://pypi.posrip.com/pypi/#{dependency_name}/json"
            stub_request(:get, private_url)
              .to_return(status: 200, body: "<!DOCTYPE html>")
          end

          it { is_expected.to eq("https://github.com/spotify/luigi") }
        end
      end
    end

    context "with a private index using /simple/ endpoint" do
      let(:credentials) do
        [Dependabot::Credential.new(
          {
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }
        ), Dependabot::Credential.new(
          {
            "type" => "python_index",
            "index-url" => "https://jfrogghdemo.jfrog.io/artifactory/api/pypi/dependabot-pip/simple",
            "token" => "testuser:testpass",
            "replaces-base" => true
          }
        )]
      end
      let(:pypi_response) { fixture("pypi", "pypi_response.json") }

      before do
        # Stub the correctly converted private registry URL (/simple/ -> /pypi/)
        private_url = "https://jfrogghdemo.jfrog.io/artifactory/api/pypi/dependabot-pip/pypi/#{dependency_name}/json"
        stub_request(:get, private_url)
          .with(basic_auth: %w(testuser testpass))
          .to_return(status: 200, body: pypi_response)
      end

      it "correctly converts /simple/ endpoint to /pypi/ endpoint for JSON API" do
        expect(source_url).to eq("https://github.com/spotify/luigi")
      end

      it "generates the correct possible listing URLs" do
        possible_urls = finder.send(:possible_listing_urls)

        # Should convert /simple/ to /pypi/ for the private registry
        expect(possible_urls).to include(
          "https://testuser:testpass@jfrogghdemo.jfrog.io/artifactory/api/pypi/dependabot-pip/pypi/luigi/json"
        )

        # Should not include the incorrect /simple/ URL for JSON API
        expect(possible_urls).not_to include(
          "https://testuser:testpass@jfrogghdemo.jfrog.io/artifactory/api/pypi/dependabot-pip/simple/luigi/json"
        )
      end

      it "does not include public PyPI in possible listing URLs" do
        possible_urls = finder.send(:possible_listing_urls)
        expect(possible_urls).not_to include(a_string_matching(/pypi\.org/))
      end

      it "does not query public PyPI even when private registry returns 404" do
        private_url = "https://jfrogghdemo.jfrog.io/artifactory/api/pypi/dependabot-pip/pypi/#{dependency_name}/json"
        stub_request(:get, private_url)
          .with(basic_auth: %w(testuser testpass))
          .to_return(status: 404, body: "")

        source_url
        expect(WebMock).not_to have_requested(:get, pypi_url)
      end

      context "when the private registry endpoint doesn't end with /simple/" do
        let(:credentials) do
          [Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://custom.registry.com/custom/path",
              "token" => "testtoken"
            }
          )]
        end

        before do
          # For non-simple endpoints, should append /json directly
          private_url = "https://custom.registry.com/custom/path/#{dependency_name}/json"
          stub_request(:get, private_url)
            .to_return(status: 200, body: pypi_response)
        end

        it "doesn't convert URLs that don't end with /simple/" do
          possible_urls = finder.send(:possible_listing_urls)

          expect(possible_urls).to include(
            "https://testtoken@custom.registry.com/custom/path/luigi/json"
          )
        end
      end
    end

    context "with a private index where 'simple' appears in both repository name and endpoint" do
      let(:credentials) do
        [Dependabot::Credential.new(
          {
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }
        ), Dependabot::Credential.new(
          {
            "type" => "python_index",
            "index-url" => "https://registry.example.com/simple/simple",
            "token" => "testuser:testpass",
            "replaces-base" => true
          }
        )]
      end
      let(:pypi_response) { fixture("pypi", "pypi_response.json") }

      before do
        # Stub the correctly converted private registry URL
        # Should convert only the trailing /simple to /pypi, leaving repository name intact
        private_url = "https://registry.example.com/simple/pypi/#{dependency_name}/json"
        stub_request(:get, private_url)
          .with(basic_auth: %w(testuser testpass))
          .to_return(status: 200, body: pypi_response)
      end

      it "correctly converts only trailing /simple/ to /pypi/, preserving 'simple' in repository name" do
        expect(source_url).to eq("https://github.com/spotify/luigi")
      end

      it "does not include public PyPI in possible listing URLs" do
        possible_urls = finder.send(:possible_listing_urls)
        expect(possible_urls).not_to include(a_string_matching(/pypi\.org/))
      end

      it "does not query public PyPI even when private registry returns 404" do
        private_url = "https://registry.example.com/simple/pypi/#{dependency_name}/json"
        stub_request(:get, private_url)
          .with(basic_auth: %w(testuser testpass))
          .to_return(status: 404, body: "")

        source_url
        expect(WebMock).not_to have_requested(:get, pypi_url)
      end

      it "generates the correct URL with 'simple' preserved in repository name" do
        possible_urls = finder.send(:possible_listing_urls)

        # Should convert only trailing /simple to /pypi, keeping repository name "simple"
        expect(possible_urls).to include(
          "https://testuser:testpass@registry.example.com/simple/pypi/luigi/json"
        )

        # Should not include the incorrect /simple/ URL for JSON API
        expect(possible_urls).not_to include(
          "https://testuser:testpass@registry.example.com/simple/simple/luigi/json"
        )

        # Should NOT incorrectly modify the repository name
        expect(possible_urls).not_to include(
          "https://testuser:testpass@registry.example.com/pypi/pypi/luigi/json"
        )
      end
    end

    context "when the dependency came from a local repository" do
      let(:pypi_response) { fixture("pypi", "pypi_response.json") }
      let(:version) { "1.0+gc.1" }

      it { is_expected.to be_nil }

      it "doesn't call pypi" do
        source_url
        expect(WebMock).not_to have_requested(:get, pypi_url).once
      end
    end

    context "when there is a bitbucket link in the pypi response" do
      let(:pypi_response) { fixture("pypi", "pypi_response_bitbucket.json") }

      it { is_expected.to eq("https://bitbucket.org/spotify/luigi") }

      it "caches the call to pypi" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, pypi_url).once
      end
    end

    context "when there is a source link in the pypi description" do
      let(:pypi_response) do
        fixture("pypi", "pypi_response_description_source.json")
      end

      context "when dealing with a different dependency" do
        before do
          stub_request(:get, "https://github.com/benjaminp/six")
            .to_return(status: 404, body: "")
        end

        it { is_expected.to be_nil }

        it "caches the call to pypi" do
          2.times { source_url }
          expect(WebMock).to have_requested(:get, pypi_url).once
        end
      end

      context "when dealing with this dependency" do
        let(:dependency_name) { "six" }

        it { is_expected.to eq("https://github.com/benjaminp/six") }

        it "caches the call to pypi" do
          2.times { source_url }
          expect(WebMock).to have_requested(:get, pypi_url).once
        end

        context "with an unexpected name" do
          let(:dependency_name) { "python-six" }

          before do
            stub_request(:get, "https://github.com/benjaminp/six")
              .to_return(status: 200, body: "python-six")
          end

          it { is_expected.to eq("https://github.com/benjaminp/six") }
        end
      end
    end

    context "when there is not a recognised source link in the pypi response" do
      let(:pypi_response) { fixture("pypi", "pypi_response_no_source.json") }

      before do
        stub_request(:get, "http://initd.org/psycopg/")
          .to_return(status: 200, body: "no details")
      end

      it { is_expected.to be_nil }

      it "caches the call to pypi" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, pypi_url).once
      end

      it "caches the call to the homepage" do
        2.times { source_url }
        expect(WebMock)
          .to have_requested(:get, "http://initd.org/psycopg/").once
      end

      context "when the homepage does an infinite redirect" do
        let(:redirect_url) { "http://initd.org/Psycopg/" }

        before do
          stub_request(:get, "http://initd.org/psycopg/")
            .to_return(status: 302, headers: { "Location" => redirect_url })
          stub_request(:get, redirect_url)
            .to_return(
              status: 302,
              headers: { "Location" => "http://initd.org/psycopg/" }
            )
        end

        it { is_expected.to be_nil }
      end

      context "when there are details on the home page" do
        before do
          stub_request(:get, "http://initd.org/psycopg/")
            .to_return(
              status: 200,
              body: fixture("psycopg_homepage.html")
            )
        end

        context "when dealing with this dependency" do
          let(:dependency_name) { "psycopg2" }

          it { is_expected.to eq("https://github.com/psycopg/psycopg2") }

          context "with an unexpected name" do
            let(:dependency_name) { "python-psycopg2" }

            before do
              stub_request(:get, "https://github.com/psycopg/psycopg2")
                .to_return(status: 200, body: "python-psycopg2")
            end

            it { is_expected.to eq("https://github.com/psycopg/psycopg2") }
          end
        end

        context "when dealing with another dependency" do
          let(:dependency_name) { "luigi" }

          before do
            stub_request(:get, "https://github.com/psycopg/psycopg2")
              .to_return(status: 200, body: "python-psycopg2")
          end

          it { is_expected.to be_nil }
        end
      end
    end

    context "when the pypi link resolves to a redirect" do
      let(:redirect_url) { "https://pypi.org/pypi/LuiGi/json" }
      let(:pypi_response) { fixture("pypi", "pypi_response.json") }

      before do
        stub_request(:get, pypi_url)
          .to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url)
          .to_return(status: 200, body: pypi_response)
      end

      it { is_expected.to eq("https://github.com/spotify/luigi") }
    end

    context "when the dependency has extras" do
      let(:dependency_name) { "celery[redis]" }
      let(:version) { "4.3" }
      let(:pypi_url) { "https://pypi.org/pypi/celery/json" }
      let(:pypi_response) { fixture("pypi", "pypi_response_extras.json") }

      it { is_expected.to eq("https://github.com/celery/celery") }
    end

    context "when the dependency source is in project_urls" do
      let(:pypi_response) { fixture("pypi", "pypi_response_project_urls_source.json") }

      it { is_expected.to eq("https://github.com/xxxxx/django-split-settings") }
    end

    context "when project_urls includes unrelated links before the source repo" do
      let(:dependency_name) { "geohelper" }
      let(:pypi_response) { fixture("pypi", "pypi_response_project_urls_prefer_matching_repo.json") }

      it "prefers the repository that matches the dependency name" do
        expect(source_url).to eq("https://github.com/example-org/geohelper")
      end

      it "parses the matching project URL only once" do
        matching_url_parse_count = 0

        allow(Dependabot::Source).to receive(:from_url).and_wrap_original do |original, url|
          matching_url_parse_count += 1 if url == "https://github.com/example-org/geohelper"
          original.call(url)
        end

        source_url

        expect(matching_url_parse_count).to eq(1)
      end
    end
  end

  describe "#homepage_url" do
    subject(:homepage_url) { finder.homepage_url }

    let(:pypi_url) { "https://pypi.org/pypi/#{dependency_name}/json" }

    before do
      stub_request(:get, pypi_url).to_return(status: 200, body: pypi_response)
    end

    context "when there is a homepage link in the pypi response" do
      let(:pypi_response) { fixture("pypi", "pypi_response_no_source.json") }

      it "returns the specified homepage" do
        expect(homepage_url).to eq("http://initd.org/psycopg/")
      end
    end
  end

  describe "#maintainer_changes" do
    subject(:maintainer_changes) { finder.maintainer_changes }

    let(:version) { "2.1.0" }
    let(:previous_version) { "2.0.0" }
    let(:pypi_version_url) { "https://pypi.org/pypi/#{dependency_name}/#{version}/json" }
    let(:pypi_previous_version_url) do
      "https://pypi.org/pypi/#{dependency_name}/#{previous_version}/json"
    end
    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: version,
        previous_version: previous_version,
        requirements: [{
          file: "requirements.txt",
          requirement: "==#{version}",
          groups: [],
          source: nil
        }],
        package_manager: "pip"
      )
    end

    context "when there is no previous version" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: version,
          requirements: [{
            file: "requirements.txt",
            requirement: "==#{version}",
            groups: [],
            source: nil
          }],
          package_manager: "pip"
        )
      end

      it { is_expected.to be_nil }
    end

    context "when the maintainers have not changed" do
      before do
        stub_request(:get, pypi_previous_version_url)
          .to_return(status: 200, body: fixture("pypi", "pypi_response_ownership_single.json"))
        stub_request(:get, pypi_version_url)
          .to_return(status: 200, body: fixture("pypi", "pypi_response_ownership_single.json"))
      end

      it { is_expected.to be_nil }
    end

    context "when all maintainers are new" do
      before do
        stub_request(:get, pypi_previous_version_url)
          .to_return(status: 200, body: fixture("pypi", "pypi_response_ownership_single.json"))
        stub_request(:get, pypi_version_url)
          .to_return(status: 200, body: fixture("pypi", "pypi_response_ownership_changed.json"))
      end

      it "returns a warning about new maintainers" do
        expect(maintainer_changes).to eq(
          "None of the maintainers for your current version of luigi are " \
          "listed as maintainers for the new version on PyPI."
        )
      end
    end

    context "when some maintainers overlap" do
      before do
        stub_request(:get, pypi_previous_version_url)
          .to_return(status: 200, body: fixture("pypi", "pypi_response_ownership_single.json"))
        stub_request(:get, pypi_version_url)
          .to_return(
            status: 200,
            body: fixture("pypi", "pypi_response_ownership_partial_change.json")
          )
      end

      it { is_expected.to be_nil }
    end

    context "when the organization changes" do
      before do
        stub_request(:get, pypi_previous_version_url)
          .to_return(status: 200, body: fixture("pypi", "pypi_response_ownership_org_old.json"))
        stub_request(:get, pypi_version_url)
          .to_return(
            status: 200,
            body: fixture("pypi", "pypi_response_ownership_org_changed.json")
          )
      end

      it "returns a warning about the organization change" do
        expect(maintainer_changes).to eq(
          "The organization that maintains luigi on PyPI has " \
          "changed since your current version."
        )
      end
    end

    context "when the organization is added" do
      before do
        stub_request(:get, pypi_previous_version_url)
          .to_return(status: 200, body: fixture("pypi", "pypi_response_ownership_single.json"))
        stub_request(:get, pypi_version_url)
          .to_return(
            status: 200,
            body: fixture("pypi", "pypi_response_ownership_org_changed.json")
          )
      end

      it { is_expected.to be_nil }
    end

    context "when the organization is removed" do
      before do
        stub_request(:get, pypi_previous_version_url)
          .to_return(status: 200, body: fixture("pypi", "pypi_response_ownership_org_old.json"))
        stub_request(:get, pypi_version_url)
          .to_return(status: 200, body: fixture("pypi", "pypi_response_ownership_single.json"))
      end

      it "returns a warning about the organization change" do
        expect(maintainer_changes).to eq(
          "The organization that maintains luigi on PyPI has " \
          "changed since your current version."
        )
      end
    end

    context "when the dependency uses a local version" do
      let(:version) { "2.1.0+build1" }
      let(:previous_version) { "2.0.0+build1" }

      it { is_expected.to be_nil }
    end

    context "when fetching ownership data times out" do
      before do
        allow(Dependabot.logger).to receive(:warn)
        stub_request(:get, pypi_previous_version_url)
          .to_raise(Excon::Error::Socket.new(IOError.new("socket error")))
        stub_request(:get, pypi_version_url)
          .to_raise(OpenSSL::SSL::SSLError.new("ssl error"))
      end

      it "returns nil and logs the request failures" do
        expect(maintainer_changes).to be_nil
        expect(Dependabot.logger).to have_received(:warn)
          .with(/Error fetching Python package ownership/).at_least(:once)
      end
    end

    context "when ownership info is not available for the new version" do
      before do
        stub_request(:get, pypi_previous_version_url)
          .to_return(status: 200, body: fixture("pypi", "pypi_response_ownership_single.json"))
        stub_request(:get, pypi_version_url)
          .to_return(status: 200, body: fixture("pypi", "pypi_response_no_ownership.json"))
      end

      it { is_expected.to be_nil }
    end

    context "when the version endpoint is not found" do
      before do
        stub_request(:get, pypi_previous_version_url)
          .to_return(status: 404, body: "")
        stub_request(:get, pypi_version_url)
          .to_return(status: 200, body: fixture("pypi", "pypi_response_ownership_single.json"))
      end

      it { is_expected.to be_nil }
    end
  end

  describe "#attestation_changes" do
    subject(:attestation_changes) { finder.attestation_changes }

    let(:dependency_name) { "luigi" }
    let(:version) { "2.6.0" }
    let(:previous_version) { "2.5.0" }
    let(:version_url) { "https://pypi.org/pypi/#{dependency_name}/#{version}/json" }
    let(:previous_version_url) { "https://pypi.org/pypi/#{dependency_name}/#{previous_version}/json" }
    let(:provenance_response) { fixture("pypi", "pypi_provenance_response.json") }
    let(:provenance_url) do
      "https://pypi.org/integrity/#{dependency_name}/#{version}/luigi-#{version}.tar.gz/provenance"
    end
    let(:previous_provenance_url) do
      "https://pypi.org/integrity/#{dependency_name}/#{previous_version}/luigi-#{previous_version}.tar.gz/provenance"
    end
    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: version,
        previous_version: previous_version,
        requirements: [{
          file: "requirements.txt",
          requirement: "==#{version}",
          groups: [],
          source: nil
        }],
        previous_requirements: [{
          file: "requirements.txt",
          requirement: "==#{previous_version}",
          groups: [],
          source: nil
        }],
        package_manager: "pip"
      )
    end

    before do
      stub_request(:get, version_url).to_return(
        status: 200,
        body: { "info" => { "name" => dependency_name, "version" => version },
                "urls" => [{ "filename" => "luigi-#{version}.tar.gz", "packagetype" => "sdist" }] }.to_json
      )
      stub_request(:get, previous_version_url).to_return(
        status: 200,
        body: { "info" => { "name" => dependency_name, "version" => previous_version },
                "urls" => [{ "filename" => "luigi-#{previous_version}.tar.gz", "packagetype" => "sdist" }] }.to_json
      )
    end

    context "when there is no previous version" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: version,
          requirements: [{
            file: "requirements.txt",
            requirement: "==#{version}",
            groups: [],
            source: nil
          }],
          package_manager: "pip"
        )
      end

      it { is_expected.to be_nil }
    end

    context "when attestation is lost between versions" do
      before do
        stub_request(:get, provenance_url)
          .to_return(status: 404, body: '{"message":"No provenance available for luigi-2.6.0.tar.gz"}')
        stub_request(:get, previous_provenance_url)
          .to_return(status: 200, body: provenance_response)
      end

      it "returns a warning about lost attestation" do
        expect(attestation_changes).to eq(
          "This version has no provenance attestation, while the previous version " \
          "(2.5.0) was attested. Review the " \
          "[package versions](https://pypi.org/project/luigi/#history) " \
          "before updating."
        )
      end
    end

    context "when both versions have attestation" do
      before do
        stub_request(:get, provenance_url)
          .to_return(status: 200, body: provenance_response)
        stub_request(:get, previous_provenance_url)
          .to_return(status: 200, body: provenance_response)
      end

      it { is_expected.to be_nil }
    end

    context "when neither version has attestation" do
      before do
        stub_request(:get, provenance_url)
          .to_return(status: 404, body: '{"message":"No provenance available for luigi-2.6.0.tar.gz"}')
        stub_request(:get, previous_provenance_url)
          .to_return(status: 404, body: '{"message":"No provenance available for luigi-2.5.0.tar.gz"}')
      end

      it { is_expected.to be_nil }
    end

    context "when attestation is gained" do
      before do
        stub_request(:get, provenance_url)
          .to_return(status: 200, body: provenance_response)
        stub_request(:get, previous_provenance_url)
          .to_return(status: 404, body: '{"message":"No provenance available for luigi-2.5.0.tar.gz"}')
      end

      it { is_expected.to be_nil }
    end

    context "when using a private index that replaces the base" do
      let(:credentials) do
        [Dependabot::Credential.new(
          {
            "type" => "python_index",
            "index-url" => "https://private.registry.com/pypi/",
            "replaces-base" => true
          }
        )]
      end

      it { is_expected.to be_nil }
    end

    context "when the version listing has no sdist entry" do
      before do
        stub_request(:get, version_url).to_return(
          status: 200,
          body: { "info" => { "name" => dependency_name, "version" => version },
                  "urls" => [{ "filename" => "luigi-#{version}-py3-none-any.whl",
                               "packagetype" => "bdist_wheel" }] }.to_json
        )
        stub_request(:get, previous_version_url).to_return(
          status: 200,
          body: { "info" => { "name" => dependency_name, "version" => previous_version },
                  "urls" => [{ "filename" => "luigi-#{previous_version}-py3-none-any.whl",
                               "packagetype" => "bdist_wheel" }] }.to_json
        )
      end

      it { is_expected.to be_nil }
    end
  end
end
