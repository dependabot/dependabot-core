# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/sbt/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Sbt::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
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
        file: "build.sbt",
        requirement: dependency_version,
        groups: [],
        source: dependency_source
      }],
      package_manager: "sbt"
    )
  end

  it_behaves_like "a dependency metadata finder"

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

    context "when there is a github link in the maven response" do
      let(:maven_response) { fixture("poms", "mockito-core-2.11.0.xml") }
      let(:dependency_name) { "org.mockito:mockito-core" }
      let(:dependency_version) { "2.11.0" }
      let(:maven_url) do
        "https://repo.maven.apache.org/maven2/org/mockito/" \
          "mockito-core/2.11.0/mockito-core-2.11.0.pom"
      end

      it { is_expected.to eq("https://github.com/mockito/mockito") }

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

    context "with a Scala cross-versioned dependency" do
      let(:dependency_name) { "org.typelevel:cats-core_2.13" }
      let(:dependency_version) { "2.9.0" }
      let(:maven_url) do
        "https://repo.maven.apache.org/maven2/org/typelevel/" \
          "cats-core_2.13/2.9.0/cats-core_2.13-2.9.0.pom"
      end
      let(:maven_response) { fixture("poms", "mockito-core-2.11.0.xml") }

      it { is_expected.to eq("https://github.com/mockito/mockito") }
    end
  end
end
