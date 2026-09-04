# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/codeql/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Codeql::MetadataFinder do
  subject(:finder) { described_class.new(dependency: dependency, credentials: credentials) }

  let(:credentials) do
    [{ "type" => "git_source", "host" => "github.com", "username" => "x-access-token", "password" => "token" }]
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "0.10.0",
      requirements: [{
        requirement: "^0.10.0",
        groups: [],
        file: "qlpack.yml",
        source: { type: "codeql_pack_registry" }
      }],
      package_manager: "codeql"
    )
  end
  let(:dependency_name) { "codeql/java-all" }

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    it "maps the pack name to a GitHub repository" do
      expect(source_url).to eq("https://github.com/codeql/java-all")
    end

    context "with an internal pack" do
      let(:dependency_name) { "internal/universal-lib" }

      it { is_expected.to eq("https://github.com/internal/universal-lib") }
    end

    context "when the pack name is not a simple scope/pack path" do
      let(:dependency_name) { "not-a-valid-pack-name" }

      it { is_expected.to be_nil }
    end
  end
end
