# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/metadata_finders/java/maven"
require_relative "../shared_examples_for_metadata_finders"

RSpec.describe Dependabot::MetadataFinders::Java::Maven do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "23.3-jre",
      requirements: [
        {
          file: "pom.xml",
          requirement: "23.3-jre",
          groups: [],
          source: nil
        }
      ],
      package_manager: "maven"
    )
  end
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end
  let(:credentials) do
    [
      {
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    ]
  end
  let(:dependency_name) { "com.google.guava:guava" }

  describe "#source_url" do
    subject(:source_url) { finder.source_url }
    let(:maven_url) do
      "https://search.maven.org/remotecontent?filepath=com/google/guava/"\
      "guava/23.3-jre/guava-23.3-jre.pom"
    end
    let(:maven_response) { fixture("java", "poms", "guava-23.3-jre.xml") }

    before do
      stub_request(:get, maven_url).to_return(status: 200, body: maven_response)
    end

    context "when there is no github link in the maven response" do
      let(:maven_response) { fixture("java", "poms", "guava-23.3-jre.xml") }

      it { is_expected.to eq(nil) }

      it "caches the call to maven" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, maven_url).once
      end
    end

    context "when the github link includes a property" do
      let(:maven_response) { fixture("java", "poms", "property_url_pom.xml") }
      it { is_expected.to eq("https://github.com/davidB/maven-scala-plugin") }
    end

    context "when there is a github link in the maven response" do
      let(:maven_response) do
        fixture("java", "poms", "mockito-core-2.11.0.xml")
      end

      it { is_expected.to eq("https://github.com/mockito/mockito") }

      it "caches the call to maven" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, maven_url).once
      end
    end

    context "when the pypi link resolves to a redirect" do
      let(:redirect_url) do
        "https://repo1.maven.org/maven2/org/mockito/mockito-core/2.11.0/"\
        "mockito-core-2.11.0.pom"
      end
      let(:maven_response) do
        fixture("java", "poms", "mockito-core-2.11.0.xml")
      end

      before do
        stub_request(:get, maven_url).
          to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url).
          to_return(status: 200, body: maven_response)
      end

      it { is_expected.to eq("https://github.com/mockito/mockito") }
    end
  end
end
