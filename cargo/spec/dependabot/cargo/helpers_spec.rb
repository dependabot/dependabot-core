# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo/helpers"

RSpec.describe Dependabot::Cargo::Helpers do
  describe ".bypass_cargo_credential_providers" do
    after do
      ENV.delete("CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS")
    end

    context "when CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS is not set" do
      before do
        ENV.delete("CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS")
      end

      it "sets it to an empty string to disable credential providers" do
        described_class.bypass_cargo_credential_providers

        expect(ENV.fetch("CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS")).to eq("")
      end
    end

    context "when CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS is already set" do
      before do
        ENV["CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS"] = "cargo:token"
      end

      it "does not overwrite the existing value" do
        described_class.bypass_cargo_credential_providers

        expect(ENV.fetch("CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS")).to eq("cargo:token")
      end
    end
  end

  describe ".sanitize_cargo_config" do
    context "when config has no credential-provider settings" do
      let(:config_content) do
        <<~TOML
          [registries.my-registry]
          index = "sparse+https://example.com/index/"
          token = "some-token"
        TOML
      end

      it "returns equivalent config with non-credential-provider keys preserved" do
        result = described_class.sanitize_cargo_config(config_content)
        parsed = TomlRB.parse(result)
        expect(parsed["registries"]["my-registry"]["index"]).to eq("sparse+https://example.com/index/")
        expect(parsed["registries"]["my-registry"]["token"]).to eq("some-token")
      end
    end

    context "when config has no registries section" do
      let(:config_content) do
        <<~TOML
          [source.crates-io]
          replace-with = "my-mirror"

          [net]
          git-fetch-with-cli = true
        TOML
      end

      it "returns equivalent config unchanged" do
        result = described_class.sanitize_cargo_config(config_content)
        parsed = TomlRB.parse(result)
        expect(parsed["source"]["crates-io"]["replace-with"]).to eq("my-mirror")
        expect(parsed["net"]["git-fetch-with-cli"]).to be true
      end
    end

    context "when config has per-registry credential-provider" do
      let(:config_content) do
        <<~TOML
          [registries.artifactory]
          index = "sparse+https://example.com/api/cargo/cargo-local/index/"
          credential-provider = "cargo:token"

          [registries.artifactory-remote]
          index = "sparse+https://example.com/api/cargo/cargo-crates-remote/index/"
          credential-provider = "cargo:token"
        TOML
      end

      it "strips credential-provider from all registries" do
        result = described_class.sanitize_cargo_config(config_content)
        parsed = TomlRB.parse(result)

        expect(parsed["registries"]["artifactory"]).not_to have_key("credential-provider")
        expect(parsed["registries"]["artifactory-remote"]).not_to have_key("credential-provider")
      end

      it "preserves index URLs" do
        result = described_class.sanitize_cargo_config(config_content)
        parsed = TomlRB.parse(result)

        expect(parsed["registries"]["artifactory"]["index"])
          .to eq("sparse+https://example.com/api/cargo/cargo-local/index/")
        expect(parsed["registries"]["artifactory-remote"]["index"])
          .to eq("sparse+https://example.com/api/cargo/cargo-crates-remote/index/")
      end
    end

    context "when config has [registry] credential-provider (e.g. for cargo publish)" do
      let(:config_content) do
        <<~TOML
          [registry]
          credential-provider = "cargo:token"
        TOML
      end

      it "strips the credential-provider" do
        result = described_class.sanitize_cargo_config(config_content)
        parsed = TomlRB.parse(result)

        expect(parsed.fetch("registry", {})).not_to have_key("credential-provider")
      end
    end

    context "when config has mixed settings" do
      let(:config_content) do
        <<~TOML
          [registries.with-cred]
          index = "sparse+https://example.com/index/"
          credential-provider = "cargo:token"

          [registries.without-cred]
          index = "sparse+https://other.example.com/index/"

          [source.crates-io]
          replace-with = "with-cred"

          [net]
          git-fetch-with-cli = true
        TOML
      end

      it "strips only credential-provider, preserves everything else" do
        result = described_class.sanitize_cargo_config(config_content)
        parsed = TomlRB.parse(result)

        expect(parsed["registries"]["with-cred"]).not_to have_key("credential-provider")
        expect(parsed["registries"]["with-cred"]["index"]).to eq("sparse+https://example.com/index/")
        expect(parsed["registries"]["without-cred"]["index"]).to eq("sparse+https://other.example.com/index/")
        expect(parsed["source"]["crates-io"]["replace-with"]).to eq("with-cred")
        expect(parsed["net"]["git-fetch-with-cli"]).to be true
      end
    end

    context "when config is malformed TOML" do
      let(:config_content) { "this is not valid toml {{{{" }

      it "raises DependencyFileNotParseable" do
        expect { described_class.sanitize_cargo_config(config_content) }
          .to raise_error(Dependabot::DependencyFileNotParseable, /Failed to parse Cargo config file/)
      end
    end
  end
end
