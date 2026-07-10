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

      it "propagates the error instead of hiding the tooling failure" do
        expect { registry_client.find_environment_files(directory) }
          .to raise_error(StandardError, "Julia helper crashed")
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

  describe "#julia_env registry authentication" do
    let(:depot_dir) { Dir.mktmpdir("julia-depot") }
    let(:registry_client) do
      described_class.new(
        credentials: [
          Dependabot::Credential.new(
            "type" => "julia_registry",
            "url" => "https://pkg.example.com",
            "token" => "s3cret"
          )
        ]
      )
    end

    after { FileUtils.rm_rf(depot_dir) }

    before do
      allow(registry_client).to receive(:julia_user_depot).and_return(depot_dir)
    end

    it "sets JULIA_PKG_SERVER to the credential URL" do
      env = registry_client.send(:julia_env)
      expect(env["JULIA_PKG_SERVER"]).to eq("https://pkg.example.com")
    end

    it "writes the token to the depot auth.toml where Pkg reads it" do
      registry_client.send(:julia_env)

      auth_file = File.join(depot_dir, "servers", "pkg.example.com", "auth.toml")
      expect(TomlRB.parse(File.read(auth_file))).to eq("access_token" => "s3cret")
    end

    context "when the token contains TOML metacharacters" do
      let(:registry_client) do
        described_class.new(
          credentials: [
            Dependabot::Credential.new(
              "type" => "julia_registry",
              "url" => "https://pkg.example.com",
              "token" => %(we"ird\\to"ken)
            )
          ]
        )
      end

      it "escapes them so the token round-trips" do
        registry_client.send(:julia_env)

        auth_file = File.join(depot_dir, "servers", "pkg.example.com", "auth.toml")
        expect(TomlRB.parse(File.read(auth_file))).to eq("access_token" => %(we"ird\\to"ken))
      end
    end

    it "does not set the unrecognized indexed env vars" do
      env = registry_client.send(:julia_env)
      expect(env.keys.grep(/JULIA_PKG_SERVER_\d/)).to be_empty
    end

    context "without a token" do
      let(:registry_client) do
        described_class.new(
          credentials: [
            Dependabot::Credential.new("type" => "julia_registry", "url" => "https://pkg.example.com")
          ]
        )
      end

      it "sets the server without writing auth.toml" do
        env = registry_client.send(:julia_env)
        expect(env["JULIA_PKG_SERVER"]).to eq("https://pkg.example.com")
        expect(File.exist?(File.join(depot_dir, "servers", "pkg.example.com", "auth.toml"))).to be(false)
      end
    end

    context "without julia_registry credentials" do
      let(:registry_client) { described_class.new(credentials: []) }

      it "does not set JULIA_PKG_SERVER" do
        expect(registry_client.send(:julia_env)).not_to have_key("JULIA_PKG_SERVER")
      end
    end
  end
end
