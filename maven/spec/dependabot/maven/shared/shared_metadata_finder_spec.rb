# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/maven/shared/shared_metadata_finder"
require "dependabot/maven/file_parser"

class TestSharedMetadataFinder < Dependabot::Maven::Shared::SharedMetadataFinder; end

RSpec.describe Dependabot::Maven::Shared::SharedMetadataFinder do
  subject(:finder) do
    TestSharedMetadataFinder.new(dependency: dependency, credentials: credentials)
  end

  let(:dependency_source) do
    { type: "maven_repo", url: "https://repo.maven.apache.org/maven2" }
  end
  let(:dependency_version) { "23.3-jre" }
  let(:dependency_name) { "com.google.guava:guava" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: [{
        file: "pom.xml",
        requirement: dependency_version,
        groups: [],
        source: dependency_source
      }],
      package_manager: "maven"
    )
  end

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    let(:maven_url) do
      "https://repo.maven.apache.org/maven2/com/google/guava/" \
        "guava/23.3-jre/guava-23.3-jre.pom"
    end
    let(:maven_response) { fixture("poms", "guava-23.3-jre.xml") }

    before do
      stub_request(:get, maven_url).to_return(status: 200, body: maven_response)
      stub_request(:get, "https://example.com/status").to_return(
        status: 200,
        body: "Not GHES",
        headers: {}
      )
    end

    context "when the github link is buried in the pom" do
      it { is_expected.to eq("https://github.com/google/guava") }

      it "caches the call to maven" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, maven_url).once
      end
    end

    context "when there is no github link in the pom" do
      let(:maven_response) { fixture("poms", "okhttp-3.10.0.xml") }
      let(:dependency_name) { "com.squareup.okhttp3:okhttp" }
      let(:dependency_version) { "3.10.0" }
      let(:maven_url) do
        "https://repo.maven.apache.org/maven2/com/squareup/okhttp3/" \
          "okhttp/3.10.0/okhttp-3.10.0.pom"
      end
      let(:parent_url) do
        "https://repo.maven.apache.org/maven2/com/squareup/okhttp3/" \
          "parent/3.10.0/parent-3.10.0.pom"
      end

      context "when there is in the parent" do
        before do
          stub_request(:get, parent_url)
            .to_return(status: 200, body: fixture("poms", "parent-3.10.0.xml"))
        end

        it { is_expected.to eq("https://github.com/square/okhttp") }
      end

      context "when there isn't in the parent, either" do
        before do
          stub_request(:get, parent_url).to_return(status: 404, body: "")
        end

        it { is_expected.to be_nil }
      end
    end

    context "when the github link includes a property" do
      let(:maven_response) { fixture("poms", "property_url_pom.xml") }

      it { is_expected.to eq("https://github.com/davidB/maven-scala-plugin") }

      context "when the property is nested" do
        let(:maven_response) { fixture("poms", "nested_property_url_pom.xml") }

        it do
          expect(source_url).to eq("https://github.com/apache/maven-checkstyle-plugin")
        end
      end
    end

    context "when there is a github link in the maven response" do
      let(:maven_response) { fixture("poms", "mockito-core-2.11.0.xml") }

      it { is_expected.to eq("https://github.com/mockito/mockito") }
    end

    context "when using a custom registry" do
      let(:dependency_source) do
        { type: "maven_repo", url: "https://custom.registry.org/maven2" }
      end
      let(:maven_url) do
        "https://custom.registry.org/maven2/com/google/guava/" \
          "guava/23.3-jre/guava-23.3-jre.pom"
      end
      let(:maven_response) { fixture("poms", "mockito-core-2.11.0.xml") }

      it { is_expected.to eq("https://github.com/mockito/mockito") }
    end

    context "when the Maven link resolves to a redirect" do
      let(:redirect_url) do
        "https://repo1.maven.org/maven2/org/mockito/mockito-core/2.11.0/" \
          "mockito-core-2.11.0.pom"
      end
      let(:maven_response) { fixture("poms", "mockito-core-2.11.0.xml") }

      before do
        stub_request(:get, maven_url)
          .to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url)
          .to_return(status: 200, body: maven_response)
      end

      it { is_expected.to eq("https://github.com/mockito/mockito") }
    end

    context "when the pom request times out" do
      before do
        stub_request(:get, maven_url).to_raise(Excon::Error::Timeout)
      end

      it { is_expected.to be_nil }
    end
  end
end
