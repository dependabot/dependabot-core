# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/dependency_grapher"
require "dependabot/npm_and_yarn/dependency_grapher/yarn_relationship_resolver"

RSpec.describe Dependabot::NpmAndYarn::DependencyGrapher::YarnRelationshipResolver do
  subject(:relationships) { described_class.new(lockfile).relationships }

  let(:lockfile) { Dependabot::DependencyFile.new(name: "yarn.lock", content: "unused helper input") }
  let(:result) do
    {
      "__metadata" => { "version" => 8 },
      "parent@^1" => {
        "version" => "1.0.0",
        "dependencies" => { "exact" => "^1", "grouped" => "^2", "sole" => "^9", "ambiguous" => "^9" }
      },
      "exact@^1" => { "version" => "1.1.0" },
      "exact@^2" => { "version" => "2.0.0" },
      "grouped@^1, grouped@^2" => { "version" => "2.1.0" },
      "sole@^1" => { "version" => "1.2.0" },
      "ambiguous@^1" => { "version" => "1.0.0" },
      "ambiguous@^2" => { "version" => "2.0.0" }
    }
  end

  before do
    allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
      .with(hash_including(function: "yarn:parseLockfile")).and_return(result)
  end

  it "preserves exact, grouped, and sole-name resolution order" do
    expect(relationships).to eq("parent@1.0.0" => %w(exact@1.1.0 grouped@2.1.0 sole@1.2.0))
  end

  context "with workspace parents" do
    let(:result) do
      super().merge("local@workspace:." => { "version" => "0.0.0-use.local", "dependencies" => { "exact" => "^1" } })
    end

    it "retains workspace relationship data" do
      expect(relationships.fetch("local@0.0.0-use.local")).to eq(["exact@1.1.0"])
    end
  end

  context "with duplicate parents" do
    let(:result) do
      super().merge(
        "parent@~1.0.0" => { "version" => "1.0.0", "dependencies" => { "exact" => "^1", "grouped" => "^1" } }
      )
    end

    it "merges and deduplicates their resolved children" do
      expect(relationships.fetch("parent@1.0.0")).to eq(%w(exact@1.1.0 grouped@2.1.0 sole@1.2.0))
    end
  end

  context "with null child data" do
    let(:result) { { "parent@^1" => { "version" => "1.0.0", "dependencies" => nil } } }

    it "preserves the empty-child skip" do
      expect(relationships).to be_empty
    end
  end
end
