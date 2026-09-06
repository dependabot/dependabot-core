# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/kotlin_toolchain/package/package_details_fetcher"

RSpec.describe Dependabot::KotlinToolchain::Package::PackageDetailsFetcher do
  let(:dependency_file) do
    Dependabot::DependencyFile.new(
      name: "module.yaml",
      content: <<~YAML
        repositories:
          - https://repo.example.test/releases
        dependencies:
          - com.example:library:1.0.0
      YAML
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "com.example:library",
      version: "1.0.0",
      requirements: [{
        file: "module.yaml",
        requirement: "1.0.0",
        groups: ["dependencies"],
        source: { type: "maven_repo", url: "https://source.example.test/maven" },
        metadata: nil
      }],
      package_manager: "kotlin_toolchain"
    )
  end
  let(:credentials) { [] }
  let(:fetcher) do
    described_class.new(
      dependency: dependency,
      dependency_files: [dependency_file],
      credentials: credentials,
      forbidden_urls: []
    )
  end

  it "uses Kotlin Toolchain repositories instead of Gradle build files" do
    urls = fetcher.send(:dependency_repository_details).map { |details| details.fetch("url") }

    expect(urls).to contain_exactly(
      "https://repo.maven.apache.org/maven2",
      "https://maven.google.com",
      "https://repo.example.test/releases",
      "https://source.example.test/maven"
    )
  end

  context "with a credential that replaces Maven Central" do
    let(:credentials) do
      [
        Dependabot::Credential.new(
          "type" => "maven_repository",
          "url" => "https://mirror.internal/repo",
          "replaces-base" => true
        )
      ]
    end

    it "drops Maven Central from the repositories it queries" do
      urls = fetcher.send(:repositories).map { |details| details.fetch("url") }

      expect(urls).to include("https://mirror.internal/repo")
      expect(urls).not_to include("https://repo.maven.apache.org/maven2")
    end
  end

  context "when Google Maven times out" do
    let(:metadata) do
      <<~XML
        <metadata>
          <groupId>com.example</groupId>
          <artifactId>library</artifactId>
          <versioning><versions><version>1.0.0</version><version>1.1.0</version></versions></versioning>
        </metadata>
      XML
    end

    before do
      stub_request(:get, "https://maven.google.com/com/example/group-index.xml").to_timeout
      stub_request(:get, %r{https://repo\.maven\.apache\.org/maven2/com/example/library/maven-metadata\.xml})
        .to_return(status: 200, body: metadata)
      stub_request(:get, %r{https://(repo|source)\.example\.test/.*/maven-metadata\.xml}).to_return(status: 404)
    end

    it "still returns the versions the other repositories know about" do
      expect(fetcher.fetch_available_versions.map { |release| release.fetch(:version).to_s })
        .to contain_exactly("1.0.0", "1.1.0")
    end
  end

  it "splits the dependency name into a group and an artifact" do
    expect(fetcher.send(:group_and_artifact_ids)).to eq(%w(com.example library))
  end

  it "is never a Gradle plugin" do
    expect(fetcher.send(:plugin?)).to be(false)
    expect(fetcher.send(:kotlin_plugin?)).to be(false)
  end

  context "with a built-in technology that publishes under another name" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "org.jetbrains.kotlin:kotlin-stdlib",
        version: "2.2.20",
        requirements: [],
        package_manager: "kotlin_toolchain",
        metadata: { maven_name: "org.jetbrains.kotlin:kotlin-stdlib" }
      )
    end

    it "resolves the published Maven coordinate" do
      expect(fetcher.send(:group_and_artifact_ids)).to eq(%w(org.jetbrains.kotlin kotlin-stdlib))
    end
  end
end
