# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bazel/update_checker"

RSpec.describe Dependabot::Bazel::UpdateChecker::RegistryClient do
  let(:client) { described_class.new }

  describe "#all_module_versions" do
    context "when module exists" do
      it "returns a list of versions" do
        github_response = [
          { "name" => "0.33.0", "type" => "dir" },
          { "name" => "0.34.0", "type" => "dir" },
          { "name" => "0.57.0", "type" => "dir" },
          { "name" => "README.md", "type" => "file" }
        ]

        allow(client).to receive(:fetch_github_api)
          .with("https://api.github.com/repos/bazelbuild/bazel-central-registry/contents/modules/rules_go")
          .and_return(github_response)

        versions = client.all_module_versions("rules_go")

        expect(versions).to contain_exactly("0.33.0", "0.34.0", "0.57.0")
        expect(versions).to eq(versions.sort)
      end

      it "sorts versions correctly" do
        github_response = [
          { "name" => "0.10.0", "type" => "dir" },
          { "name" => "0.2.0", "type" => "dir" },
          { "name" => "0.1.0", "type" => "dir" }
        ]

        allow(client).to receive(:fetch_github_api)
          .with("https://api.github.com/repos/bazelbuild/bazel-central-registry/contents/modules/test_module")
          .and_return(github_response)

        versions = client.all_module_versions("test_module")

        expect(versions).to eq(["0.1.0", "0.2.0", "0.10.0"])
      end
    end

    context "when module does not exist" do
      it "returns empty array for 404 response" do
        error = Dependabot::DependabotError.new("404 not found")
        allow(client).to receive(:fetch_github_api)
          .and_raise(error)

        versions = client.all_module_versions("nonexistent_module")

        expect(versions).to eq([])
      end

      it "re-raises other errors" do
        error = Dependabot::DependabotError.new("500 server error")
        allow(client).to receive(:fetch_github_api)
          .and_raise(error)

        expect do
          client.all_module_versions("test_module")
        end.to raise_error(Dependabot::DependabotError, "500 server error")
      end
    end

    context "when response is invalid" do
      it "handles non-array response gracefully" do
        allow(client).to receive(:fetch_github_api)
          .and_return({ "message" => "not an array" })

        versions = client.all_module_versions("test_module")

        expect(versions).to eq([])
      end
    end
  end

  describe "#latest_module_version" do
    context "when module has versions" do
      it "returns the latest version" do
        allow(client).to receive(:all_module_versions)
          .with("rules_go")
          .and_return(["0.33.0", "0.34.0", "0.57.0"])

        latest = client.latest_module_version("rules_go")

        expect(latest).to eq("0.57.0")
      end

      it "handles version comparison correctly" do
        allow(client).to receive(:all_module_versions)
          .with("test_module")
          .and_return(["1.0.0", "1.10.0", "1.2.0"])

        latest = client.latest_module_version("test_module")

        expect(latest).to eq("1.10.0")
      end
    end

    context "when module has no versions" do
      it "returns nil" do
        allow(client).to receive(:all_module_versions)
          .with("empty_module")
          .and_return([])

        latest = client.latest_module_version("empty_module")

        expect(latest).to be_nil
      end
    end
  end

  describe "#get_metadata" do
    it "constructs metadata from version information" do
      versions = ["0.33.0", "0.34.0", "0.57.0"]
      allow(client).to receive(:all_module_versions)
        .with("rules_go")
        .and_return(versions)

      metadata = client.get_metadata("rules_go")

      expect(metadata).to eq(
        {
          "name" => "rules_go",
          "versions" => versions,
          "latest_version" => "0.57.0"
        }
      )
    end

    it "returns nil when module has no versions" do
      allow(client).to receive(:all_module_versions)
        .with("nonexistent")
        .and_return([])

      metadata = client.get_metadata("nonexistent")

      expect(metadata).to be_nil
    end
  end

  describe "#get_source" do
    context "when source.json exists" do
      it "returns parsed source information" do
        source_content = {
          "url" => "https://github.com/bazelbuild/rules_go/releases/download/v0.57.0/rules_go-v0.57.0.zip",
          "integrity" => "sha256-pynI7SRHyQ/hQAd2iQecoKz7dYDsQWN/MS1lDOnZPZY="
        }.to_json

        allow(client).to receive(:fetch_raw_content)
          .with("https://raw.githubusercontent.com/bazelbuild/bazel-central-registry/main/modules/rules_go/0.57.0/source.json")
          .and_return(source_content)

        source = client.get_source("rules_go", "0.57.0")

        expect(source).to include(
          "url" => "https://github.com/bazelbuild/rules_go/releases/download/v0.57.0/rules_go-v0.57.0.zip",
          "integrity" => "sha256-pynI7SRHyQ/hQAd2iQecoKz7dYDsQWN/MS1lDOnZPZY="
        )
      end
    end

    context "when source.json does not exist" do
      it "returns nil" do
        allow(client).to receive(:fetch_raw_content)
          .and_return(nil)

        source = client.get_source("rules_go", "nonexistent")

        expect(source).to be_nil
      end
    end

    context "when source.json is invalid JSON" do
      it "returns nil and logs warning" do
        allow(client).to receive(:fetch_raw_content)
          .and_return("invalid json content")

        allow(Dependabot.logger).to receive(:warn)

        source = client.get_source("rules_go", "0.57.0")

        expect(source).to be_nil
        expect(Dependabot.logger).to have_received(:warn)
          .with(a_string_matching(/Failed to parse source/))
      end
    end
  end

  describe "#get_module_bazel" do
    context "when MODULE.bazel exists" do
      it "returns MODULE.bazel content" do
        module_content = <<~BAZEL
          module(
              name = "rules_go",
              version = "0.57.0",
          )
        BAZEL

        allow(client).to receive(:fetch_raw_content)
          .with("https://raw.githubusercontent.com/bazelbuild/bazel-central-registry/main/modules/rules_go/0.57.0/MODULE.bazel")
          .and_return(module_content)

        content = client.get_module_bazel("rules_go", "0.57.0")

        expect(content).to eq(module_content)
      end
    end

    context "when MODULE.bazel does not exist" do
      it "returns nil" do
        allow(client).to receive(:fetch_raw_content)
          .and_return(nil)

        content = client.get_module_bazel("rules_go", "nonexistent")

        expect(content).to be_nil
      end
    end
  end

  describe "#module_version_exists?" do
    it "returns true when version exists" do
      allow(client).to receive(:get_source)
        .with("rules_go", "0.57.0")
        .and_return({ "url" => "https://example.com" })

      exists = client.module_version_exists?("rules_go", "0.57.0")

      expect(exists).to be true
    end

    it "returns false when version does not exist" do
      allow(client).to receive(:get_source)
        .with("rules_go", "nonexistent")
        .and_return(nil)

      exists = client.module_version_exists?("rules_go", "nonexistent")

      expect(exists).to be false
    end
  end
end
