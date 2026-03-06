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

  describe "HEX_AUTH_ERROR_PATTERNS" do
    subject(:patterns) { described_class::HEX_AUTH_ERROR_PATTERNS }

    [
      ["No authenticated organization found for my-repo_1.", "my-repo_1", nil],
      ['Public key fingerprint mismatch for repo "jfrog-hex-2"', "jfrog-hex-2", nil],
      ['Missing credentials for "my_repo"', "my_repo", nil],
      ['Downloading public key for repo "repo-9" failed with code: 401', "repo-9", nil],
      ['Registry "my-jfrog" does not serve a public key and none was provided', "my-jfrog", nil],
      ['Embedded public key fingerprint mismatch for repo "repo-1"', "repo-1", nil],
      ['Invalid PEM public key for repo "repo-2"', "repo-2", nil],
      ["Failed to fetch record for my_repo:my_org", "my_repo", "my_org"],
      ["Failed to fetch record for my_repo", "my_repo", nil]
    ].each do |message, expected_repo, expected_org|
      it "matches '#{message}' and extracts repo=#{expected_repo}" do
        match = patterns.lazy.filter_map { |p| message.match(p) }.first
        expect(match).not_to be_nil, "Expected a pattern to match: #{message}"
        expect(match[:repo]).to eq(expected_repo)
        expect(match[:org]).to eq(expected_org) if expected_org
      end
    end

    it "does not match unrelated error messages" do
      match = patterns.lazy.filter_map { |p| "Something else went wrong".match(p) }.first
      expect(match).to be_nil
    end
  end
end
