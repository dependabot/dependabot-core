# typed: false
# frozen_string_literal: true

require "spec_helper"
require "ostruct"
require "base64"
require "octokit"
require "dependabot/bazel/update_checker"

RSpec.describe Dependabot::Bazel::UpdateChecker::RegistryClient do
  let(:credentials) { [] }
  let(:client) { described_class.new(credentials: credentials) }
  let(:octokit_client) { instance_double(Octokit::Client) }
  let(:github_client) { instance_double(Dependabot::Clients::GithubWithRetries) }

  before do
    allow(client).to receive(:github_client).and_return(github_client)
    allow(github_client).to receive(:method_missing) do |method_name, *args, &block|
      octokit_client.public_send(method_name, *args, &block)
    end
  end

  describe "#all_module_versions" do
    context "when module exists" do
      it "returns a list of versions" do
        github_response = [
          { name: "0.33.0", type: "dir" },
          { name: "0.34.0", type: "dir" },
          { name: "0.57.0", type: "dir" },
          { name: "README.md", type: "file" }
        ]

        allow(octokit_client).to receive(:contents)
          .with("bazelbuild/bazel-central-registry", hash_including(path: "modules/rules_go"))
          .and_return(github_response)

        versions = client.all_module_versions("rules_go")

        expect(versions).to contain_exactly("0.33.0", "0.34.0", "0.57.0")
        expect(versions).to eq(versions.sort)
      end

      it "sorts versions correctly" do
        github_response = [
          { name: "0.10.0", type: "dir" },
          { name: "0.2.0", type: "dir" },
          { name: "0.1.0", type: "dir" }
        ]

        allow(octokit_client).to receive(:contents)
          .with("bazelbuild/bazel-central-registry", hash_including(path: "modules/test_module"))
          .and_return(github_response)

        versions = client.all_module_versions("test_module")

        expect(versions).to eq(["0.1.0", "0.2.0", "0.10.0"])
      end
    end

    context "when module does not exist" do
      it "returns empty array for 404 response" do
        allow(octokit_client).to receive(:contents)
          .and_raise(Octokit::NotFound)

        versions = client.all_module_versions("nonexistent_module")

        expect(versions).to eq([])
      end

      it "re-raises other errors" do
        error = StandardError.new("500 server error")
        allow(octokit_client).to receive(:contents)
          .and_raise(error)

        expect do
          client.all_module_versions("test_module")
        end.to raise_error(StandardError, "500 server error")
      end
    end

    context "when response is invalid" do
      it "handles non-array response gracefully" do
        allow(octokit_client).to receive(:contents)
          .and_return({ message: "not an array" })

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

        # Simulate GitHub API returning base64 encoded content
        encoded_content = Base64.encode64(source_content)
        github_response = OpenStruct.new(content: encoded_content)

        allow(octokit_client).to receive(:contents)
          .with("bazelbuild/bazel-central-registry", hash_including(path: "modules/rules_go/0.57.0/source.json"))
          .and_return(github_response)

        source = client.get_source("rules_go", "0.57.0")

        expect(source).to include(
          "url" => "https://github.com/bazelbuild/rules_go/releases/download/v0.57.0/rules_go-v0.57.0.zip",
          "integrity" => "sha256-pynI7SRHyQ/hQAd2iQecoKz7dYDsQWN/MS1lDOnZPZY="
        )
      end
    end

    context "when source.json does not exist" do
      it "returns nil" do
        allow(octokit_client).to receive(:contents)
          .and_raise(Octokit::NotFound)

        source = client.get_source("rules_go", "nonexistent")

        expect(source).to be_nil
      end
    end

    context "when source.json is invalid JSON" do
      it "returns nil and logs warning" do
        # Simulate GitHub API returning base64 encoded invalid content
        encoded_content = Base64.encode64("invalid json content")
        github_response = OpenStruct.new(content: encoded_content)

        allow(octokit_client).to receive(:contents)
          .and_return(github_response)

        allow(Dependabot.logger).to receive(:warn)

        source = client.get_source("rules_go", "0.57.0")

        expect(source).to be_nil
        expect(Dependabot.logger).to have_received(:warn)
          .with(a_string_matching(/Failed to get source/))
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

        # Simulate GitHub API returning base64 encoded content
        encoded_content = Base64.encode64(module_content)
        github_response = OpenStruct.new(content: encoded_content)

        allow(octokit_client).to receive(:contents)
          .with("bazelbuild/bazel-central-registry", hash_including(path: "modules/rules_go/0.57.0/MODULE.bazel"))
          .and_return(github_response)

        content = client.get_module_bazel("rules_go", "0.57.0")

        expect(content).to eq(module_content)
      end
    end

    context "when MODULE.bazel does not exist" do
      it "returns nil" do
        allow(octokit_client).to receive(:contents)
          .and_raise(Octokit::NotFound)

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
