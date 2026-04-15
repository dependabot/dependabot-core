# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/maven/shared/shared_maven_repository_client"
require "dependabot/maven/version"

class TestMavenRepositoryClient < Dependabot::Maven::Shared::SharedMavenRepositoryClient
  attr_reader :dependency
  attr_reader :credentials

  def initialize(dependency:, credentials:, repositories:)
    @dependency = dependency
    @credentials = credentials
    @test_repositories = repositories
  end

  def repositories
    @test_repositories
  end
end

RSpec.describe Dependabot::Maven::Shared::SharedMavenRepositoryClient do
  subject(:client) do
    TestMavenRepositoryClient.new(
      dependency: dependency,
      credentials: credentials,
      repositories: repositories
    )
  end

  let(:dependency_name) { "com.google.guava:guava" }
  let(:dependency_version) { "23.3-jre" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: [{
        requirement: "23.3-jre",
        file: "pom.xml",
        groups: ["dependencies"],
        source: nil,
        metadata: { packaging_type: "jar" }
      }],
      package_manager: "maven"
    )
  end
  let(:credentials) { [] }
  let(:maven_central) { "https://repo.maven.apache.org/maven2" }
  let(:repositories) do
    [{ "url" => maven_central, "auth_headers" => {} }]
  end

  describe "#dependency_parts" do
    it "splits the dependency name into group path and artifact ID" do
      group_path, artifact_id = client.dependency_parts

      expect(group_path).to eq("com/google/guava")
      expect(artifact_id).to eq("guava")
    end

    context "with a deeply nested group ID" do
      let(:dependency_name) { "org.apache.commons:commons-lang3" }

      it "converts dots to slashes in the group path" do
        group_path, artifact_id = client.dependency_parts

        expect(group_path).to eq("org/apache/commons")
        expect(artifact_id).to eq("commons-lang3")
      end
    end

    it "caches the result" do
      first_result = client.dependency_parts
      second_result = client.dependency_parts

      expect(first_result).to equal(second_result)
    end
  end

  describe "#dependency_base_url" do
    it "constructs the base URL from repo URL, group path, and artifact ID" do
      url = client.dependency_base_url(maven_central)

      expect(url).to eq("#{maven_central}/com/google/guava/guava")
    end
  end

  describe "#dependency_metadata_url" do
    it "appends maven-metadata.xml to the base URL" do
      url = client.dependency_metadata_url(maven_central)

      expect(url).to eq("#{maven_central}/com/google/guava/guava/maven-metadata.xml")
    end
  end

  describe "#dependency_files_url" do
    let(:version) { Dependabot::Maven::Version.new("23.6-jre") }

    it "constructs the artifact file URL" do
      url = client.dependency_files_url(maven_central, version)

      expect(url).to eq("#{maven_central}/com/google/guava/guava/23.6-jre/guava-23.6-jre.jar")
    end

    context "with a classifier" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: dependency_version,
          requirements: [{
            requirement: "23.3-jre",
            file: "pom.xml",
            groups: ["dependencies"],
            source: nil,
            metadata: { packaging_type: "jar", classifier: "sources" }
          }],
          package_manager: "maven"
        )
      end

      it "includes the classifier in the URL" do
        url = client.dependency_files_url(maven_central, version)

        expect(url).to eq("#{maven_central}/com/google/guava/guava/23.6-jre/guava-23.6-jre-sources.jar")
      end
    end

    context "without packaging_type metadata" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: dependency_version,
          requirements: [{
            requirement: "23.3-jre",
            file: "pom.xml",
            groups: ["dependencies"],
            source: nil,
            metadata: {}
          }],
          package_manager: "maven"
        )
      end

      it "defaults to jar" do
        url = client.dependency_files_url(maven_central, version)

        expect(url).to eq("#{maven_central}/com/google/guava/guava/23.6-jre/guava-23.6-jre.jar")
      end
    end
  end

  describe "#extract_metadata_from_xml" do
    let(:xml_body) do
      <<~XML
        <metadata>
          <versioning>
            <versions>
              <version>23.0</version>
              <version>23.3-jre</version>
              <version>23.6-jre</version>
              <version>not-a-version!</version>
            </versions>
          </versioning>
        </metadata>
      XML
    end
    let(:xml) { Nokogiri::XML(xml_body) }

    it "extracts valid versions from the XML document" do
      results = client.extract_metadata_from_xml(xml, maven_central)

      versions = results.map { |r| r[:version].to_s }
      expect(versions).to contain_exactly("23.0", "23.3-jre", "23.6-jre")
    end

    it "includes the source URL for each version" do
      results = client.extract_metadata_from_xml(xml, maven_central)

      results.each do |result|
        expect(result[:source_url]).to eq(maven_central)
      end
    end

    it "returns Version objects" do
      results = client.extract_metadata_from_xml(xml, maven_central)

      results.each do |result|
        expect(result[:version]).to be_a(Dependabot::Maven::Version)
      end
    end

    context "with an empty versions list" do
      let(:xml_body) do
        <<~XML
          <metadata>
            <versioning>
              <versions/>
            </versioning>
          </metadata>
        XML
      end

      it "returns an empty array" do
        results = client.extract_metadata_from_xml(xml, maven_central)

        expect(results).to eq([])
      end
    end
  end

  describe "#extract_version_details_from_html" do
    let(:html_body) do
      <<~HTML
        <html><body><pre>
        <a href="../">../</a>
        <a href="23.0/" title="23.0/">23.0/</a>                  2017-08-04 12:00         -
        <a href="23.3-jre/" title="23.3-jre/">23.3-jre/</a>      2017-09-27 14:30         -
        <a href="23.6-jre/" title="23.6-jre/">23.6-jre/</a>      2017-11-22 16:45         -
        </pre></body></html>
      HTML
    end
    let(:html) { Nokogiri::HTML(html_body) }

    it "extracts version strings and release dates from the HTML listing" do
      results = client.extract_version_details_from_html(html)

      expect(results.keys).to contain_exactly("23.0", "23.3-jre", "23.6-jre")
    end

    it "parses release dates" do
      results = client.extract_version_details_from_html(html)

      expect(results["23.0"][:release_date]).to be_a(Time)
      expect(results["23.6-jre"][:release_date]).to be_a(Time)
    end

    context "with unparseable dates" do
      let(:html_body) do
        <<~HTML
          <html><body><pre>
          <a href="1.0/" title="1.0/">1.0/</a>                  not-a-date         -
          </pre></body></html>
        HTML
      end

      it "sets release_date to nil" do
        results = client.extract_version_details_from_html(html)

        expect(results["1.0"][:release_date]).to be_nil
      end
    end

    context "with invalid version strings" do
      let(:html_body) do
        <<~HTML
          <html><body><pre>
          <a href="23.0/" title="23.0/">23.0/</a>                    2017-08-04 12:00         -
          <a href="not-a-version!/" title="not-a-version!/">not-a-version!/</a>  2017-09-01 10:00         -
          </pre></body></html>
        HTML
      end

      it "only includes versions that pass version_class.correct?" do
        results = client.extract_version_details_from_html(html)

        expect(results).to have_key("23.0")
        expect(results).not_to have_key("not-a-version!")
      end
    end
  end

  describe "#check_response" do
    let(:repository_url) { "https://private.repo.example.com/maven2" }

    context "when the response status is 200" do
      let(:response) { instance_double(Excon::Response, status: 200) }

      it "does not add to forbidden URLs" do
        client.check_response(response, repository_url)

        expect(client.forbidden_urls).to be_empty
      end
    end

    context "when the response status is 401" do
      let(:response) { instance_double(Excon::Response, status: 401) }

      it "adds the URL to forbidden URLs" do
        client.check_response(response, repository_url)

        expect(client.forbidden_urls).to include(repository_url)
      end

      it "does not add duplicates" do
        client.check_response(response, repository_url)
        client.check_response(response, repository_url)

        expect(client.forbidden_urls.count(repository_url)).to eq(1)
      end
    end

    context "when the response status is 403" do
      let(:response) { instance_double(Excon::Response, status: 403) }

      it "adds the URL to forbidden URLs" do
        client.check_response(response, repository_url)

        expect(client.forbidden_urls).to include(repository_url)
      end
    end

    context "when the URL is the central repo" do
      let(:response) { instance_double(Excon::Response, status: 401) }
      let(:repository_url) { "https://repo.maven.apache.org/maven2" }

      it "does not add central repo to forbidden URLs" do
        client.check_response(response, repository_url)

        expect(client.forbidden_urls).to be_empty
      end
    end
  end

  describe "#handle_registry_error" do
    context "when the URL is not the central repo" do
      let(:url) { "https://private.repo.example.com/maven2" }
      let(:error) { Excon::Error::Timeout.new("timeout") }

      it "does not raise" do
        expect { client.handle_registry_error(url, error, nil) }.not_to raise_error
      end
    end

    context "when the URL is the central repo" do
      let(:url) { "https://repo.maven.apache.org/maven2" }
      let(:error) { Excon::Error::Timeout.new("connection timed out") }

      it "raises a RegistryError with the error message" do
        expect { client.handle_registry_error(url, error, nil) }
          .to raise_error(Dependabot::RegistryError)
      end

      context "with a response object" do
        let(:response) { instance_double(Excon::Response, status: 503, body: "Service Unavailable") }

        it "raises a RegistryError with response details" do
          expect { client.handle_registry_error(url, error, response) }
            .to raise_error(Dependabot::RegistryError) { |e|
              expect(e.status).to eq(503)
            }
        end
      end
    end
  end

  describe "#fetch_dependency_metadata" do
    let(:metadata_url) { "#{maven_central}/com/google/guava/guava/maven-metadata.xml" }
    let(:repository_details) { { "url" => maven_central, "auth_headers" => {} } }

    context "when the registry returns a valid XML response" do
      before do
        stub_request(:get, metadata_url)
          .to_return(status: 200, body: fixture("maven_central_metadata", "with_release.xml"))
      end

      it "returns a parsed Nokogiri XML document" do
        result = client.fetch_dependency_metadata(repository_details)

        expect(result).to be_a(Nokogiri::XML::Document)
        expect(result.css("versions > version").count).to be > 0
      end
    end

    context "when the registry returns a 404" do
      before do
        stub_request(:get, metadata_url).to_return(status: 404)
      end

      it "returns nil" do
        result = client.fetch_dependency_metadata(repository_details)

        expect(result).to be_nil
      end
    end

    context "when the request times out" do
      before do
        stub_request(:get, metadata_url).to_raise(Excon::Error::Timeout)
      end

      it "returns nil for non-central repos" do
        non_central_details = { "url" => "https://private.repo.example.com", "auth_headers" => {} }
        # Need to stub the non-central URL too
        stub_request(:get, "https://private.repo.example.com/com/google/guava/guava/maven-metadata.xml")
          .to_raise(Excon::Error::Timeout)

        result = client.fetch_dependency_metadata(non_central_details)

        expect(result).to be_nil
      end
    end

    context "when the URI is invalid" do
      let(:repository_details) { { "url" => "ht!tp://bad url", "auth_headers" => {} } }

      before do
        stub_request(:get, /bad%20url/).to_raise(URI::InvalidURIError)
      end

      it "returns nil" do
        result = client.fetch_dependency_metadata(repository_details)

        expect(result).to be_nil
      end
    end
  end

  describe "#fetch_dependency_metadata_from_html" do
    let(:base_url) { "#{maven_central}/com/google/guava/guava" }
    let(:repository_details) { { "url" => maven_central, "auth_headers" => {} } }

    context "when the registry returns a valid HTML response" do
      before do
        stub_request(:get, base_url)
          .to_return(status: 200, body: fixture("maven_central_metadata", "with_release.html"))
      end

      it "returns a parsed Nokogiri HTML document" do
        result = client.fetch_dependency_metadata_from_html(repository_details)

        expect(result).to be_a(Nokogiri::HTML::Document)
      end
    end

    context "when the registry returns a 404" do
      before do
        stub_request(:get, base_url).to_return(status: 404)
      end

      it "returns nil" do
        result = client.fetch_dependency_metadata_from_html(repository_details)

        expect(result).to be_nil
      end
    end
  end

  describe "#released?" do
    let(:version) { Dependabot::Maven::Version.new("23.6-jre") }
    let(:artifact_url) { "#{maven_central}/com/google/guava/guava/23.6-jre/guava-23.6-jre.jar" }

    context "when the artifact exists" do
      before do
        stub_request(:head, artifact_url).to_return(status: 200)
      end

      it "returns true" do
        expect(client.released?(version)).to be(true)
      end
    end

    context "when the artifact does not exist" do
      before do
        stub_request(:head, artifact_url).to_return(status: 404)
      end

      it "returns false" do
        expect(client.released?(version)).to be(false)
      end
    end

    context "when the request times out" do
      before do
        stub_request(:head, artifact_url).to_raise(Excon::Error::Timeout)
      end

      it "returns false" do
        expect(client.released?(version)).to be(false)
      end
    end

    context "when the result is cached" do
      before do
        stub_request(:head, artifact_url).to_return(status: 200)
      end

      it "returns the cached result on subsequent calls" do
        first_result = client.released?(version)
        # Remove the stub — if it hits the network again, it would fail
        WebMock.reset!
        second_result = client.released?(version)

        expect(first_result).to eq(second_result)
      end
    end

    context "when the result is false" do
      before do
        stub_request(:head, artifact_url).to_return(status: 404)
      end

      it "caches false results without re-requesting" do
        expect(client.released?(version)).to be(false)
        # Remove the stub — second call should use cache, not network
        WebMock.reset!
        expect(client.released?(version)).to be(false)
      end
    end

    context "with multiple repositories" do
      let(:private_repo) { "https://private.repo.example.com/maven2" }
      let(:private_artifact_url) { "#{private_repo}/com/google/guava/guava/23.6-jre/guava-23.6-jre.jar" }
      let(:repositories) do
        [
          { "url" => private_repo, "auth_headers" => {} },
          { "url" => maven_central, "auth_headers" => {} }
        ]
      end

      before do
        stub_request(:head, private_artifact_url).to_return(status: 404)
        stub_request(:head, artifact_url).to_return(status: 200)
      end

      it "returns true if any repository has the artifact" do
        expect(client.released?(version)).to be(true)
      end
    end
  end

  describe "#credentials_repository_details" do
    let(:credentials) do
      [
        Dependabot::Credential.new({ "type" => "maven_repository", "url" => "https://repo.example.com/maven2/" }),
        Dependabot::Credential.new({ "type" => "git_source", "host" => "github.com" }),
        Dependabot::Credential.new({ "type" => "maven_repository", "url" => "https://repo2.example.com/maven2" })
      ]
    end

    it "returns only maven_repository credentials" do
      result = client.credentials_repository_details

      expect(result.length).to eq(2)
    end

    it "strips trailing slashes from URLs" do
      result = client.credentials_repository_details

      urls = result.map { |r| r["url"] }
      expect(urls).to include("https://repo.example.com/maven2")
      expect(urls).not_to include("https://repo.example.com/maven2/")
    end

    it "includes auth headers for each repository" do
      result = client.credentials_repository_details

      expect(result).to all(have_key("auth_headers"))
    end
  end

  describe "#central_repo_url" do
    it "returns the default Maven Central URL" do
      expect(client.central_repo_url).to eq("https://repo.maven.apache.org/maven2")
    end
  end

  describe "#central_repo_urls" do
    it "returns both HTTP and HTTPS variants" do
      urls = client.central_repo_urls

      expect(urls).to contain_exactly(
        "http://repo.maven.apache.org/maven2",
        "https://repo.maven.apache.org/maven2"
      )
    end
  end

  describe "#dependency_metadata" do
    let(:metadata_url) { "#{maven_central}/com/google/guava/guava/maven-metadata.xml" }
    let(:repository_details) { { "url" => maven_central, "auth_headers" => {} } }

    before do
      stub_request(:get, metadata_url)
        .to_return(status: 200, body: fixture("maven_central_metadata", "with_release.xml"))
    end

    it "caches the result per repository" do
      first_result = client.dependency_metadata(repository_details)
      # Reset stubs — second call should use cache
      WebMock.reset!
      second_result = client.dependency_metadata(repository_details)

      expect(first_result).to equal(second_result)
    end

    it "fetches separately for different repositories" do
      other_repo = "https://other.repo.example.com/maven2"
      other_metadata_url = "#{other_repo}/com/google/guava/guava/maven-metadata.xml"
      other_details = { "url" => other_repo, "auth_headers" => {} }

      other_body = "<metadata><versioning><versions>" \
                   "<version>1.0</version>" \
                   "</versions></versioning></metadata>"
      stub_request(:get, other_metadata_url)
        .to_return(status: 200, body: other_body)

      result1 = client.dependency_metadata(repository_details)
      result2 = client.dependency_metadata(other_details)

      expect(result1).not_to equal(result2)
    end
  end

  describe "#dependency_metadata_from_html" do
    let(:base_url) { "#{maven_central}/com/google/guava/guava" }
    let(:repository_details) { { "url" => maven_central, "auth_headers" => {} } }

    before do
      stub_request(:get, base_url)
        .to_return(status: 200, body: fixture("maven_central_metadata", "with_release.html"))
    end

    it "caches the result per repository" do
      first_result = client.dependency_metadata_from_html(repository_details)
      WebMock.reset!
      second_result = client.dependency_metadata_from_html(repository_details)

      expect(first_result).to equal(second_result)
    end
  end

  describe "#version_class" do
    it "delegates to the dependency" do
      expect(client.version_class).to eq(Dependabot::Maven::Version)
    end
  end
end
