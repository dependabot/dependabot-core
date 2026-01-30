# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo/helpers"

RSpec.describe Dependabot::Cargo::Helpers do
  describe ".setup_credentials_in_environment" do
    after do
      # Clean up environment variables set during tests
      ENV.delete("CARGO_REGISTRIES_MY_REGISTRY_TOKEN")
      ENV.delete("CARGO_REGISTRIES_ANOTHER_REGISTRY_TOKEN")
      ENV.delete("CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS")
    end

    context "when credentials array is empty" do
      let(:credentials) { [] }

      it "does not set any token environment variables" do
        described_class.setup_credentials_in_environment(credentials)

        expect(ENV.fetch("CARGO_REGISTRIES_MY_REGISTRY_TOKEN", nil)).to be_nil
      end

      it "sets the global credential providers" do
        described_class.setup_credentials_in_environment(credentials)

        expect(ENV.fetch("CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS", nil)).to eq("cargo:token")
      end
    end

    context "when credential type is not cargo_registry" do
      let(:credentials) do
        [Dependabot::Credential.new({ "type" => "git_source", "registry" => "my-registry", "token" => "secret" })]
      end

      it "does not set any token environment variables" do
        described_class.setup_credentials_in_environment(credentials)

        expect(ENV.fetch("CARGO_REGISTRIES_MY_REGISTRY_TOKEN", nil)).to be_nil
      end
    end

    context "when registry is nil" do
      let(:credentials) do
        [Dependabot::Credential.new({ "type" => "cargo_registry", "token" => "secret" })]
      end

      it "does not set any token environment variables" do
        described_class.setup_credentials_in_environment(credentials)

        expect(ENV.fetch("CARGO_REGISTRIES__TOKEN", nil)).to be_nil
      end
    end

    context "when token is nil" do
      let(:credentials) do
        [Dependabot::Credential.new({ "type" => "cargo_registry", "registry" => "my-registry" })]
      end

      it "does not set any token environment variables" do
        described_class.setup_credentials_in_environment(credentials)

        expect(ENV.fetch("CARGO_REGISTRIES_MY_REGISTRY_TOKEN", nil)).to be_nil
      end
    end

    context "when registry and token are present" do
      let(:credentials) do
        [Dependabot::Credential.new({ "type" => "cargo_registry", "registry" => "my-registry", "token" => "secret" })]
      end

      it "sets the token environment variable with uppercase registry name and hyphens replaced with underscores" do
        described_class.setup_credentials_in_environment(credentials)

        expect(ENV.fetch("CARGO_REGISTRIES_MY_REGISTRY_TOKEN", nil)).to eq("secret")
      end

      it "sets the global credential providers" do
        described_class.setup_credentials_in_environment(credentials)

        expect(ENV.fetch("CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS", nil)).to eq("cargo:token")
      end
    end

    context "when multiple cargo_registry credentials are provided" do
      let(:credentials) do
        [
          Dependabot::Credential.new({ "type" => "cargo_registry", "registry" => "my-registry", "token" => "token1" }),
          Dependabot::Credential.new(
            {
              "type" => "cargo_registry", "registry" => "another-registry", "token" => "token2"
            }
          )
        ]
      end

      it "sets token environment variables for all registries" do
        described_class.setup_credentials_in_environment(credentials)

        expect(ENV.fetch("CARGO_REGISTRIES_MY_REGISTRY_TOKEN", nil)).to eq("token1")
        expect(ENV.fetch("CARGO_REGISTRIES_ANOTHER_REGISTRY_TOKEN", nil)).to eq("token2")
      end
    end

    context "when environment variable is already set" do
      let(:credentials) do
        [Dependabot::Credential.new(
          {
            "type" => "cargo_registry", "registry" => "my-registry", "token" => "new-token"
          }
        )]
      end

      before do
        ENV["CARGO_REGISTRIES_MY_REGISTRY_TOKEN"] = "existing-token"
      end

      it "does not overwrite the existing value" do
        described_class.setup_credentials_in_environment(credentials)

        expect(ENV.fetch("CARGO_REGISTRIES_MY_REGISTRY_TOKEN", nil)).to eq("existing-token")
      end
    end
  end
end
