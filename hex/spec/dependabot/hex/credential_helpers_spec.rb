# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/hex/credential_helpers"

RSpec.describe Dependabot::Hex::CredentialHelpers do
  extend T::Sig

  describe ".organization_credentials" do
    subject(:organization_credentials) { described_class.organization_credentials(credentials) }

    sig { returns(T::Array[Dependabot::Credential]) }
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

    sig { returns(T::Array[Dependabot::Credential]) }
    let(:credentials) do
      [
        Dependabot::Credential.new(
          { "type" => "hex_repository", "url" => "url", "auth_key" => "auth_key",
            "public_key_fingerprint" => "public_key_fingerprint" }
        )
      ]
    end

    it "populates the credentials with default properties" do
      expect(repo_credentials).to eq(["hex_repository", "url", "auth_key", "public_key_fingerprint", ""])
    end

    context "with a public key" do
      sig { returns(T::Array[Dependabot::Credential]) }
      let(:credentials) do
        [
          Dependabot::Credential.new(
            { "type" => "hex_repository", "repo" => "repo", "url" => "url", "public_key" => "public_key" }
          )
        ]
      end

      it "includes the public key" do
        expect(repo_credentials).to eq(%w(hex_repository repo url) + ["", "", "public_key"])
      end
    end

    context "with keys spelled as in dependabot.yml" do
      sig { returns(T::Array[Dependabot::Credential]) }
      let(:credentials) do
        [
          Dependabot::Credential.new(
            { "type" => "hex_repository", "repo" => "repo", "url" => "url", "auth-key" => "auth_key",
              "public-key-fingerprint" => "public_key_fingerprint", "public-key" => "public_key" }
          )
        ]
      end

      it "reads them" do
        expect(repo_credentials).to eq(%w(hex_repository repo url auth_key public_key_fingerprint public_key))
      end
    end
  end
end
