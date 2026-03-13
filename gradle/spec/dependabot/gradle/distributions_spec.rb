# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/gradle/distributions"

RSpec.describe Dependabot::Gradle::Distributions do
  describe ".find_credential" do
    it "returns nil when no gradle-distribution credential exists" do
      credentials = [
        Dependabot::Credential.new({ "type" => "maven_repository", "url" => "https://repo.example.com" })
      ]
      expect(described_class.find_credential(credentials)).to be_nil
    end

    it "returns the gradle-distribution credential when it exists" do
      credential = Dependabot::Credential.new({
        "type" => "gradle-distribution",
        "url" => "https://mycompany.example.com/gradle"
      })
      credentials = [
        Dependabot::Credential.new({ "type" => "maven_repository", "url" => "https://repo.example.com" }),
        credential
      ]
      expect(described_class.find_credential(credentials)).to eq(credential)
    end
  end

  describe ".distribution_url" do
    context "when no gradle-distribution credential exists" do
      it "returns the default distribution URL" do
        credentials = [
          Dependabot::Credential.new({ "type" => "maven_repository", "url" => "https://repo.example.com" })
        ]
        expect(described_class.distribution_url(credentials)).to eq("https://services.gradle.org")
      end
    end

    context "when a gradle-distribution credential exists" do
      it "returns the custom distribution URL" do
        credentials = [
          Dependabot::Credential.new({
            "type" => "gradle-distribution",
            "url" => "https://mycompany.example.com/gradle/"
          })
        ]
        expect(described_class.distribution_url(credentials)).to eq("https://mycompany.example.com/gradle")
      end

      it "strips trailing slashes from the URL" do
        credentials = [
          Dependabot::Credential.new({
            "type" => "gradle-distribution",
            "url" => "https://mycompany.example.com/gradle///"
          })
        ]
        expect(described_class.distribution_url(credentials)).to eq("https://mycompany.example.com/gradle")
      end
    end
  end

  describe ".auth_headers_for" do
    context "when no gradle-distribution credential exists" do
      it "returns empty headers" do
        credentials = []
        expect(described_class.auth_headers_for(credentials)).to eq({})
      end
    end

    context "when credential has no auth" do
      it "returns empty headers" do
        credentials = [
          Dependabot::Credential.new({
            "type" => "gradle-distribution",
            "url" => "https://mycompany.example.com/gradle"
          })
        ]
        expect(described_class.auth_headers_for(credentials)).to eq({})
      end
    end

    context "when credential has username and password" do
      it "returns Basic auth headers" do
        credentials = [
          Dependabot::Credential.new({
            "type" => "gradle-distribution",
            "url" => "https://mycompany.example.com/gradle",
            "username" => "octocat",
            "password" => "secret123"
          })
        ]
        expected_token = Base64.strict_encode64("octocat:secret123")
        expect(described_class.auth_headers_for(credentials)).to eq({
          "Authorization" => "Basic #{expected_token}"
        })
      end
    end

    context "when credential has only username but no password" do
      it "returns empty headers" do
        credentials = [
          Dependabot::Credential.new({
            "type" => "gradle-distribution",
            "url" => "https://mycompany.example.com/gradle",
            "username" => "octocat"
          })
        ]
        expect(described_class.auth_headers_for(credentials)).to eq({})
      end
    end
  end

  describe ".distribution_requirements?" do
    it "returns true when requirements have gradle-distribution source type" do
      requirements = [{ source: { type: "gradle-distribution" } }]
      expect(described_class.distribution_requirements?(requirements)).to be true
    end

    it "returns false when requirements have no gradle-distribution source type" do
      requirements = [{ source: { type: "maven_repo" } }]
      expect(described_class.distribution_requirements?(requirements)).to be false
    end
  end
end
