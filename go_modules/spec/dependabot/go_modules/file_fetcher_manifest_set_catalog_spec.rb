# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/manifest_sets"
require "dependabot/go_modules/file_fetcher"

RSpec.describe Dependabot::GoModules::FileFetcher do
  describe "manifest-set catalog rules" do
    let(:ecosystem) { Dependabot::ManifestSets.catalog.ecosystem("golang") }

    it "matches go.mod, which the fetcher accepts" do
      expect(ecosystem.rule_matches?("go.mod")).to be(true)
      expect(described_class.required_files_in?(["go.mod"])).to be(true)
    end

    # go.work workspaces are reported as unresolvable rather than described by a rule; go.sum and the
    # other module files are inputs but never define a set.
    it "does not match workspace or checksum files" do
      %w(go.work go.work.sum go.sum go.env GO.MOD go.mod.bak vendor).each do |name|
        expect(ecosystem.rule_matches?(name)).to be(false), name
      end
    end

    it "assigns every go.mod directory to the go_modules owner" do
      expect(ecosystem.select_owner(%w(go.mod go.sum)).owner&.id).to eq("go_modules")
    end
  end
end
