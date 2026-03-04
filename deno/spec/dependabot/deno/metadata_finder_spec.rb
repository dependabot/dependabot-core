# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/deno/metadata_finder"
require "dependabot/dependency"

RSpec.describe Dependabot::Deno::MetadataFinder do
  let(:finder) do
    described_class.new(
      dependency: dependency,
      credentials: credentials
    )
  end
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end

  context "with a jsr dependency" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "@std/path",
        version: "1.0.0",
        requirements: [{
          requirement: "^1.0.0",
          file: "deno.json",
          groups: ["imports"],
          source: { type: "jsr" }
        }],
        package_manager: "deno"
      )
    end

    it "returns nil source for jsr packages" do
      expect(finder.source_url).to be_nil
    end
  end

  context "with an npm dependency" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "chalk",
        version: "5.3.0",
        requirements: [{
          requirement: "^5.3.0",
          file: "deno.json",
          groups: ["imports"],
          source: { type: "npm" }
        }],
        package_manager: "deno"
      )
    end

    before do
      stub_request(:get, "https://registry.npmjs.org/chalk")
        .to_return(
          status: 200,
          body: {
            "repository" => { "type" => "git", "url" => "https://github.com/chalk/chalk" },
            "versions" => {}
          }.to_json
        )
    end

    it "finds the source URL from npm" do
      expect(finder.source_url).to eq("https://github.com/chalk/chalk")
    end
  end
end
