# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/kotlin_toolchain/metadata_finder"

RSpec.describe Dependabot::KotlinToolchain::MetadataFinder do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "org.jetbrains.kotlin:kotlin-cli",
      version: "0.11.1",
      requirements: [],
      package_manager: "kotlin_toolchain",
      metadata: { wrapper: true }
    )
  end

  it "links wrapper updates to the Kotlin Toolchain project" do
    finder = described_class.new(dependency: dependency, credentials: [])

    expect(finder.source_url).to eq("https://github.com/JetBrains/kotlin-toolchain")
  end

  context "with a regular Maven dependency" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "com.example:library",
        version: "1.0.0",
        requirements: [{
          file: "module.yaml",
          requirement: "1.0.0",
          groups: ["dependencies"],
          source: { type: "maven_repo", url: "https://repo.example.test/maven" },
          metadata: nil
        }],
        package_manager: "kotlin_toolchain"
      )
    end
    let(:finder) { described_class.new(dependency: dependency, credentials: []) }

    before do
      stub_request(:get, /repo\.example\.test/).to_return(status: 404, body: "")
      stub_request(:get, /repo\.maven\.apache\.org/).to_return(status: 404, body: "")
    end

    it "looks the source up in the Maven repository" do
      expect(finder.source_url).to be_nil
      expect(WebMock).to have_requested(:get, %r{repo\.example\.test/maven/com/example/library}).at_least_once
    end

    it "is never treated as a Gradle plugin and uses the Kotlin Toolchain fetcher" do
      expect(finder.send(:plugin?)).to be(false)
      expect(finder.send(:file_fetcher_class)).to eq(Dependabot::KotlinToolchain::FileFetcher)
    end
  end
end
