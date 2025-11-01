# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia/registry_client"

RSpec.describe Dependabot::Julia::RegistryClient do
  let(:registry_client) { described_class.new(credentials: []) }

  describe "#find_environment_files" do
    let(:directory) { "/tmp/test_project" }

    context "when Julia helper successfully finds files" do
      before do
        allow(registry_client).to receive(:call_julia_helper).with(
          function: "find_environment_files",
          args: { directory: directory }
        ).and_return({
          "project_file" => "/tmp/test_project/Project.toml",
          "manifest_file" => "/tmp/test_project/Manifest.toml"
        })
      end

      it "returns both project and manifest file paths" do
        result = registry_client.find_environment_files(directory)

        expect(result).to eq(
          {
            "project_file" => "/tmp/test_project/Project.toml",
            "manifest_file" => "/tmp/test_project/Manifest.toml"
          }
        )
      end
    end

    context "when only Project.toml exists (no manifest yet)" do
      before do
        allow(registry_client).to receive(:call_julia_helper).with(
          function: "find_environment_files",
          args: { directory: directory }
        ).and_return({
          "project_file" => "/tmp/test_project/Project.toml",
          "manifest_file" => "/tmp/test_project/Manifest.toml"
        })
      end

      it "returns both paths even if manifest doesn't exist yet" do
        result = registry_client.find_environment_files(directory)

        expect(result["project_file"]).to eq("/tmp/test_project/Project.toml")
        expect(result["manifest_file"]).to eq("/tmp/test_project/Manifest.toml")
      end
    end

    context "when files are in a workspace with parent manifest" do
      before do
        allow(registry_client).to receive(:call_julia_helper).with(
          function: "find_environment_files",
          args: { directory: directory }
        ).and_return({
          "project_file" => "/tmp/test_project/SubPackage/Project.toml",
          "manifest_file" => "/tmp/test_project/Manifest.toml"
        })
      end

      it "returns project in subdirectory and manifest in parent" do
        result = registry_client.find_environment_files(directory)

        expect(result["project_file"]).to eq("/tmp/test_project/SubPackage/Project.toml")
        expect(result["manifest_file"]).to eq("/tmp/test_project/Manifest.toml")
      end
    end

    context "when Julia helper returns an error" do
      before do
        allow(registry_client).to receive(:call_julia_helper).with(
          function: "find_environment_files",
          args: { directory: directory }
        ).and_return({
          "error" => "No Project.toml found"
        })
      end

      it "returns empty hash" do
        result = registry_client.find_environment_files(directory)

        expect(result).to eq({})
      end
    end

    context "when Julia helper raises an exception" do
      before do
        allow(registry_client).to receive(:call_julia_helper).with(
          function: "find_environment_files",
          args: { directory: directory }
        ).and_raise(StandardError, "Julia helper crashed")
      end

      it "logs warning and returns empty hash" do
        expect(Dependabot.logger).to receive(:warn).with(
          /Failed to find environment files.*Julia helper crashed/
        )

        result = registry_client.find_environment_files(directory)

        expect(result).to eq({})
      end
    end

    context "when finding JuliaProject.toml" do
      before do
        allow(registry_client).to receive(:call_julia_helper).with(
          function: "find_environment_files",
          args: { directory: directory }
        ).and_return({
          "project_file" => "/tmp/test_project/JuliaProject.toml",
          "manifest_file" => "/tmp/test_project/JuliaManifest.toml"
        })
      end

      it "handles Julia-prefixed file names" do
        result = registry_client.find_environment_files(directory)

        expect(result["project_file"]).to eq("/tmp/test_project/JuliaProject.toml")
        expect(result["manifest_file"]).to eq("/tmp/test_project/JuliaManifest.toml")
      end
    end

    context "when finding version-specific manifest" do
      before do
        allow(registry_client).to receive(:call_julia_helper).with(
          function: "find_environment_files",
          args: { directory: directory }
        ).and_return({
          "project_file" => "/tmp/test_project/Project.toml",
          "manifest_file" => "/tmp/test_project/Manifest-v1.12.toml"
        })
      end

      it "returns version-specific manifest path" do
        result = registry_client.find_environment_files(directory)

        expect(result["project_file"]).to eq("/tmp/test_project/Project.toml")
        expect(result["manifest_file"]).to eq("/tmp/test_project/Manifest-v1.12.toml")
      end
    end
  end
end
