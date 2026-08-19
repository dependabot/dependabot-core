# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/npm_and_yarn/registry_parser"

RSpec.describe Dependabot::NpmAndYarn::RegistryParser do
  subject(:parser) do
    described_class.new(
      resolved_url: resolved_url,
      credentials: credentials
    )
  end

  let(:credentials) do
    [
      Dependabot::Credential.new(
        "type" => "npm_registry",
        "registry" => "example.com/victim-npm",
        "token" => "victim-token"
      )
    ]
  end

  # url_for_relevant_cred is invoked when the resolved URL does not match
  # the standard tarball format patterns (Gemfury, MyGet/Bintray, Nexus).
  # Use metadata-style URLs (without /-/ tarball segment) to test it directly.

  describe "path-segment-aware credential matching via #registry_source_for" do
    context "when the resolved URL is within the configured registry path" do
      # Metadata URL — does not trigger the tarball-format branches
      let(:resolved_url) { "https://example.com/victim-npm/my-package" }

      it "returns the configured registry URL" do
        result = parser.registry_source_for("my-package")
        expect(result).to eq({ type: "registry", url: "https://example.com/victim-npm" })
      end
    end

    context "when the resolved URL is under a sibling path that shares a path prefix" do
      # /victim-npm-evil shares the prefix /victim-npm but is a different path segment
      let(:resolved_url) { "https://example.com/victim-npm-evil/my-package" }

      it "does not attribute the URL to the victim-npm registry" do
        result = parser.registry_source_for("my-package")
        expect(result[:url]).to eq("https://example.com")
        # Must NOT return the credential registry — that would mean credentials leaked
        expect(result[:url]).not_to eq("https://example.com/victim-npm")
      end
    end

    context "when the resolved URL includes an explicit non-default port" do
      let(:resolved_url) { "https://example.com:8443/victim-npm/my-package" }

      it "returns a well-formed registry URL and preserves the port" do
        result = parser.registry_source_for("my-package")
        expect(result[:url]).to eq("https://example.com:8443/victim-npm")
      end
    end

    context "when the resolved URL is under a completely different path" do
      let(:resolved_url) { "https://example.com/other-path/my-package" }

      it "does not attribute the URL to the victim-npm registry" do
        result = parser.registry_source_for("my-package")
        expect(result[:url]).not_to eq("https://example.com/victim-npm")
      end
    end

    context "when the resolved URL is on a completely different host" do
      let(:resolved_url) { "https://other.example.com/victim-npm/my-package" }

      it "does not attribute the URL to the victim-npm registry" do
        result = parser.registry_source_for("my-package")
        expect(result[:url]).not_to eq("https://example.com/victim-npm")
      end
    end

    context "when the registry is a plain hostname with no path restriction" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            "type" => "npm_registry",
            "registry" => "registry.npmjs.org",
            "token" => "npmjs-token"
          )
        ]
      end
      let(:resolved_url) { "https://registry.npmjs.org/some-package" }

      it "matches any path on the host" do
        result = parser.registry_source_for("some-package")
        expect(result[:url]).to eq("https://registry.npmjs.org")
      end
    end

    context "when the registry URL uses https:// scheme and has a path" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            "type" => "npm_registry",
            "registry" => "https://host.example.com/team-a/npm",
            "token" => "team-a-token"
          )
        ]
      end

      context "when the resolved URL is within the registry path" do
        let(:resolved_url) { "https://host.example.com/team-a/npm/my-pkg" }

        it "matches the registry" do
          result = parser.registry_source_for("my-pkg")
          expect(result[:url]).to eq("https://host.example.com/team-a/npm")
        end
      end

      context "when the resolved URL shares only a path prefix" do
        let(:resolved_url) { "https://host.example.com/team-a-evil/npm/my-pkg" }

        it "does not match the team-a credential" do
          result = parser.registry_source_for("my-pkg")
          expect(result[:url]).not_to eq("https://host.example.com/team-a/npm")
        end
      end

      context "when the resolved URL has a different scheme than the credential registry" do
        let(:resolved_url) { "http://host.example.com/team-a/npm/my-pkg" }

        it "does not match the https credential and returns a well-formed URL" do
          result = parser.registry_source_for("my-pkg")
          expect(result[:url]).not_to eq("https://host.example.com/team-a/npm")
          expect(result[:url]).not_to include("https://host.example.com/team-a/npm")
        end
      end
    end
  end
end
