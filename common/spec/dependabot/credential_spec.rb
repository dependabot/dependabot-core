# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"

RSpec.describe Dependabot::Credential do
  describe "#replaces_base?" do
    it "returns true when replaces-base is true" do
      cred = described_class.new({ "type" => "npm_registry", "replaces-base" => true })
      expect(cred.replaces_base?).to be true
    end

    it "returns false when replaces-base is not set" do
      cred = described_class.new({ "type" => "npm_registry" })
      expect(cred.replaces_base?).to be false
    end
  end

  describe "#scope" do
    it "returns nil when scope is not set" do
      cred = described_class.new({ "type" => "npm_registry", "registry" => "npm.example.com" })
      expect(cred.scope).to be_nil
    end

    it "returns an array with a single scope string" do
      cred = described_class.new(
        {
          "type" => "npm_registry",
          "registry" => "npm.example.com",
          "scope" => "@my-company"
        }
      )
      expect(cred.scope).to eq(["@my-company"])
    end

    it "returns the array as-is when scope is an array" do
      cred = described_class.new(
        {
          "type" => "npm_registry",
          "registry" => "npm.example.com",
          "scope" => ["@org1", "@org2"]
        }
      )
      expect(cred.scope).to eq(["@org1", "@org2"])
    end

    it "does not expose scope in the underlying hash" do
      cred = described_class.new(
        {
          "type" => "npm_registry",
          "registry" => "npm.example.com",
          "scope" => "@my-company"
        }
      )
      expect(cred["scope"]).to be_nil
      expect(cred.to_h).not_to have_key("scope")
    end
  end

  describe "#[]" do
    it "accesses credential fields" do
      cred = described_class.new({ "type" => "npm_registry", "registry" => "npm.example.com" })
      expect(cred["type"]).to eq("npm_registry")
      expect(cred["registry"]).to eq("npm.example.com")
    end
  end

  describe "#merge" do
    it "merges two credentials" do
      cred1 = described_class.new({ "type" => "npm_registry", "registry" => "npm.example.com" })
      cred2 = described_class.new({ "token" => "secret" })
      merged = cred1.merge(cred2)
      expect(merged["type"]).to eq("npm_registry")
      expect(merged["token"]).to eq("secret")
    end
  end
end
