# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/hex/credential_helpers"

RSpec.describe Dependabot::Hex::CredentialHelpers do
  describe ".organization_credentials" do
    subject(:organization_credentials) { described_class.organization_credentials(credentials) }

    let(:credentials) do
      [
        Dependabot::Credential.new(
          { "type" => "hex_organization", "organization" => "organization",
            "token" => "token" }
        )
      ]
    end

    it "populates the credentials with default properties" do
      expect(organization_credentials).to eq(%w(hex_organization organization token))
    end
  end

  describe ".repo_credentials" do
    subject(:repo_credentials) { described_class.repo_credentials(credentials) }

    let(:credentials) do
      [
        Dependabot::Credential.new(
          { "type" => "hex_repository", "url" => "url", "auth_key" => "auth_key",
            "public_key_fingerprint" => "public_key_fingerprint" }
        )
      ]
    end

    it "populates the credentials with default properties" do
      expect(repo_credentials).to eq(%w(hex_repository url auth_key public_key_fingerprint) + [""])
    end

    context "when a public_key is provided" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            { "type" => "hex_repository", "url" => "url", "auth_key" => "auth_key",
              "public_key_fingerprint" => "SHA256:abc123",
              "public_key" => "-----BEGIN PUBLIC KEY-----\nMIIBIjAN...\n-----END PUBLIC KEY-----" }
          )
        ]
      end

      it "includes the public_key in the serialized credentials" do
        expect(repo_credentials).to eq(
          %w(hex_repository url auth_key SHA256:abc123) +
          ["-----BEGIN PUBLIC KEY-----\nMIIBIjAN...\n-----END PUBLIC KEY-----"]
        )
      end
    end

    context "when public_key is not provided" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            { "type" => "hex_repository", "url" => "url", "auth_key" => "auth_key",
              "public_key_fingerprint" => "SHA256:abc123" }
          )
        ]
      end

      it "defaults public_key to an empty string" do
        expect(repo_credentials).to eq(%w(hex_repository url auth_key SHA256:abc123) + [""])
      end
    end
  end
end
