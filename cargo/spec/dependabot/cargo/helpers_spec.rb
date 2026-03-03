# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo/helpers"

RSpec.describe Dependabot::Cargo::Helpers do
  describe ".disable_cargo_credential_providers" do
    after do
      ENV.delete("CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS")
      ENV.delete("CARGO_REGISTRIES_MY_REGISTRY_CREDENTIAL_PROVIDER")
      ENV.delete("CARGO_REGISTRIES_ANOTHER_REGISTRY_CREDENTIAL_PROVIDER")
      ENV.delete("CARGO_REGISTRIES_ARTIFACTORY_CREDENTIAL_PROVIDER")
      ENV.delete("CARGO_REGISTRIES_ARTIFACTORY_REMOTE_CREDENTIAL_PROVIDER")
    end

    context "when credentials array is empty and no config" do
      let(:credentials) { [] }

      it "sets the global credential providers to empty string" do
        described_class.disable_cargo_credential_providers(credentials)

        expect(ENV.fetch("CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS")).to eq("")
      end

      it "does not set any per-registry credential provider overrides" do
        described_class.disable_cargo_credential_providers(credentials)

        expect(ENV.fetch("CARGO_REGISTRIES_MY_REGISTRY_CREDENTIAL_PROVIDER", nil)).to be_nil
      end
    end

    context "when CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS is already set" do
      before do
        ENV["CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS"] = "cargo:token"
      end

      it "does not overwrite the existing value" do
        described_class.disable_cargo_credential_providers([])

        expect(ENV.fetch("CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS")).to eq("cargo:token")
      end
    end

    context "when credentials contain cargo_registry entries with registry names" do
      let(:credentials) do
        [
          Dependabot::Credential.new({ "type" => "cargo_registry", "registry" => "my-registry", "token" => "t" }),
          Dependabot::Credential.new({ "type" => "cargo_registry", "registry" => "another-registry" })
        ]
      end

      it "disables the per-registry credential provider for each registry" do
        described_class.disable_cargo_credential_providers(credentials)

        expect(ENV.fetch("CARGO_REGISTRIES_MY_REGISTRY_CREDENTIAL_PROVIDER")).to eq("")
        expect(ENV.fetch("CARGO_REGISTRIES_ANOTHER_REGISTRY_CREDENTIAL_PROVIDER")).to eq("")
      end
    end

    context "when credentials have nil registry (org-level config)" do
      let(:credentials) do
        [Dependabot::Credential.new({ "type" => "cargo_registry", "token" => "secret" })]
      end

      it "skips the credential" do
        described_class.disable_cargo_credential_providers(credentials)

        expect(ENV.fetch("CARGO_REGISTRIES__CREDENTIAL_PROVIDER", nil)).to be_nil
      end
    end

    context "when cargo config content has registries" do
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

      it "disables credential providers for registries found in the config" do
        described_class.disable_cargo_credential_providers([], cargo_config_content: config_content)

        expect(ENV.fetch("CARGO_REGISTRIES_ARTIFACTORY_CREDENTIAL_PROVIDER")).to eq("")
        expect(ENV.fetch("CARGO_REGISTRIES_ARTIFACTORY_REMOTE_CREDENTIAL_PROVIDER")).to eq("")
      end
    end

    context "when registries appear in both credentials and config" do
      let(:credentials) do
        [Dependabot::Credential.new({ "type" => "cargo_registry", "registry" => "artifactory", "token" => "t" })]
      end

      let(:config_content) do
        <<~TOML
          [registries.artifactory]
          index = "sparse+https://example.com/api/cargo/cargo-local/index/"
          credential-provider = "cargo:token"

          [registries.artifactory-remote]
          index = "sparse+https://example.com/api/cargo/cargo-crates-remote/index/"
        TOML
      end

      it "disables credential providers for the union of both sources" do
        described_class.disable_cargo_credential_providers(credentials, cargo_config_content: config_content)

        expect(ENV.fetch("CARGO_REGISTRIES_ARTIFACTORY_CREDENTIAL_PROVIDER")).to eq("")
        expect(ENV.fetch("CARGO_REGISTRIES_ARTIFACTORY_REMOTE_CREDENTIAL_PROVIDER")).to eq("")
      end
    end

    context "when per-registry env var already set by developer" do
      before do
        ENV["CARGO_REGISTRIES_MY_REGISTRY_CREDENTIAL_PROVIDER"] = "cargo:token"
      end

      let(:credentials) do
        [Dependabot::Credential.new({ "type" => "cargo_registry", "registry" => "my-registry" })]
      end

      it "does not overwrite the existing value" do
        described_class.disable_cargo_credential_providers(credentials)

        expect(ENV.fetch("CARGO_REGISTRIES_MY_REGISTRY_CREDENTIAL_PROVIDER")).to eq("cargo:token")
      end
    end

    context "when cargo config content is malformed" do
      let(:config_content) { "this is not valid toml {{{{" }

      it "does not raise and still processes credentials" do
        credentials = [
          Dependabot::Credential.new({ "type" => "cargo_registry", "registry" => "my-registry" })
        ]

        expect do
          described_class.disable_cargo_credential_providers(credentials, cargo_config_content: config_content)
        end.not_to raise_error

        expect(ENV.fetch("CARGO_REGISTRIES_MY_REGISTRY_CREDENTIAL_PROVIDER")).to eq("")
      end
    end
  end
end
