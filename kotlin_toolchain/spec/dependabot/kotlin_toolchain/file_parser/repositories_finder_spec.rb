# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/kotlin_toolchain/file_parser/repositories_finder"

RSpec.describe Dependabot::KotlinToolchain::FileParser::RepositoriesFinder do
  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "module.yaml",
        content: <<~YAML
          repositories:
            - mavenCentral
            - google
            - mavenLocal
            - https://jitpack.io/
            - "not a url"
            - ftp://repo.example.test/mirror
            - id: snapshots
              url: https://repo.example.test/snapshots/
          tasks:
            testJvm:
              dependsOn: [ :plugins:prepareJvm ]
        YAML
      )
    ]
  end

  it "combines defaults and declared HTTP repositories" do
    expect(described_class.new(dependency_files: dependency_files).repository_urls).to contain_exactly(
      "https://repo.maven.apache.org/maven2",
      "https://maven.google.com",
      "https://jitpack.io",
      "https://repo.example.test/snapshots"
    )
  end

  context "with a credential that replaces Maven Central" do
    let(:credentials) do
      [
        Dependabot::Credential.new(
          "type" => "maven_repository",
          "url" => "https://mirror.internal/repo/",
          "replaces-base" => true
        )
      ]
    end

    it "queries the mirror instead of Maven Central" do
      urls = described_class.new(dependency_files: dependency_files, credentials: credentials).repository_urls

      expect(urls).to include("https://mirror.internal/repo")
      expect(urls).not_to include("https://repo.maven.apache.org/maven2")
    end
  end

  context "without declared repositories" do
    let(:dependency_files) do
      [Dependabot::DependencyFile.new(name: "module.yaml", content: "product: jvm/app\n")]
    end

    it "falls back to the default repositories" do
      expect(described_class.new(dependency_files: dependency_files).repository_urls).to contain_exactly(
        "https://repo.maven.apache.org/maven2",
        "https://maven.google.com"
      )
    end
  end
end
