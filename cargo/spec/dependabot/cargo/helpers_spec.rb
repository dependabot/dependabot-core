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
    context "when config has no credential-provider lines" do
      let(:config_content) do
        <<~TOML
          [registries.my-registry]
          index = "sparse+https://example.com/index/"

          [registries.another-registry]
          index = "sparse+https://other.example.com/index/"
        TOML
      end

      it "returns the content unchanged" do
        result = described_class.sanitize_cargo_config(config_content)
        expect(result).to eq(config_content)
      end
    end

    context "when config has per-registry credential-provider lines" do
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

      it "strips the credential-provider lines" do
        result = described_class.sanitize_cargo_config(config_content)
        expect(result).not_to include("credential-provider")
        expect(result).to include('index = "sparse+https://example.com/api/cargo/cargo-local/index/"')
        expect(result).to include('index = "sparse+https://example.com/api/cargo/cargo-crates-remote/index/"')
      end
    end

    context "when config has credential-provider with different spacing" do
      let(:config_content) do
        <<~TOML
          [registries.my-registry]
          index = "sparse+https://example.com/index/"
          credential-provider   =   "cargo:token"
        TOML
      end

      it "strips the credential-provider line regardless of whitespace" do
        result = described_class.sanitize_cargo_config(config_content)
        expect(result).not_to include("credential-provider")
        expect(result).to include('index = "sparse+https://example.com/index/"')
      end
    end

    context "when config has mixed registries with and without credential-provider" do
      let(:config_content) do
        <<~TOML
          [registries.with-cred]
          index = "sparse+https://example.com/index/"
          credential-provider = "cargo:token"

          [registries.without-cred]
          index = "sparse+https://other.example.com/index/"

          [source.crates-io]
          replace-with = "with-cred"
        TOML
      end

      it "strips only the credential-provider lines" do
        result = described_class.sanitize_cargo_config(config_content)
        expect(result).not_to include("credential-provider")
        expect(result).to include('[registries.with-cred]')
        expect(result).to include('[registries.without-cred]')
        expect(result).to include('[source.crates-io]')
        expect(result).to include('replace-with = "with-cred"')
      end
    end
  end
end
