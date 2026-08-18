# typed: false
# frozen_string_literal: true

require "spec_helper"
require "base64"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/fetched_files"

RSpec.describe Dependabot::FetchedFiles do
  let(:dependency_file) do
    Dependabot::DependencyFile.new(
      name: "Gemfile",
      content: "source 'https://rubygems.org'",
      directory: "/app",
      support_file: true,
      content_encoding: "utf-8"
    )
  end

  let(:fetched_files) do
    described_class.new(
      dependency_files: [dependency_file],
      base_commit_sha: "abc123",
      directory_fetch_errors: directory_fetch_errors
    )
  end

  let(:directory_fetch_errors) { {} }

  describe "#serialize / .deserialize round-trip" do
    subject(:round_tripped) { described_class.deserialize(fetched_files.serialize) }

    it "uses the base64_dependency_files contract with Base64-encoded content" do
      payload = JSON.parse(fetched_files.serialize)

      expect(payload).to have_key("base64_dependency_files")
      encoded = payload["base64_dependency_files"].first["content"]
      expect(Base64.decode64(encoded)).to eq("source 'https://rubygems.org'")
    end

    it "omits directory_fetch_errors when there are none" do
      expect(JSON.parse(fetched_files.serialize)).not_to have_key("directory_fetch_errors")
    end

    it "preserves the base commit SHA" do
      expect(round_tripped.base_commit_sha).to eq("abc123")
    end

    it "preserves the dependency files" do
      file = round_tripped.dependency_files.first

      expect(file.name).to eq("Gemfile")
      expect(file.content).to eq("source 'https://rubygems.org'")
      expect(file.directory).to eq("/app")
      expect(file.support_file?).to be(true)
      expect(file.content_encoding).to eq("utf-8")
    end

    context "when a directory has a PathDependenciesNotReachable error" do
      let(:directory_fetch_errors) do
        { "/app" => Dependabot::PathDependenciesNotReachable.new("some/path") }
      end

      it "rehydrates the error class and message" do
        error = round_tripped.directory_fetch_errors["/app"]

        expect(error).to be_a(Dependabot::PathDependenciesNotReachable)
        expect(error.message).to include("some/path")
      end
    end

    context "when a directory has a generic fetch error" do
      let(:directory_fetch_errors) do
        { "/app" => Dependabot::DependabotError.new("boom") }
      end

      it "rehydrates a generic error preserving the message" do
        error = round_tripped.directory_fetch_errors["/app"]

        expect(error).to be_a(Dependabot::DependabotError)
        expect(error.message).to eq("boom")
      end
    end
  end
end
