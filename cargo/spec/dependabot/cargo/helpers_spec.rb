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
end
