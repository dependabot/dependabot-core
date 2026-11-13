# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/manifest_sets"
require "dependabot/uv/file_fetcher"

RSpec.describe Dependabot::Uv::FileFetcher do
  describe "manifest-set catalog rules" do
    let(:ecosystem) { Dependabot::ManifestSets.catalog.ecosystem("pypi") }
    let(:uv_files) { Dependabot::Uv::FileFetcher::ECOSYSTEM_SPECIFIC_FILES }

    it "uses exactly the uv fetcher's ecosystem-specific files as the uv owner's selectors" do
      expect(ecosystem.owner("uv")&.when_any_basename).to match_array(uv_files)
    end

    # uv.lock defines a set on its own (so deleting pyproject.toml alone does not make the set absent), but
    # the uv fetcher only accepts it next to pyproject.toml.
    it "matches every uv selector as a manifest-set file the uv fetcher reads" do
      uv_files.each do |name|
        expect(ecosystem.rule_matches?(name)).to be(true)
        expect(described_class.required_files_in?([name, "pyproject.toml"])).to be(true)
      end
    end

    it "selects uv as the owner whenever a uv selector is present" do
      expect(ecosystem.select_owner(%w(requirements.txt pyproject.toml uv.lock)).owner&.id).to eq("uv")
    end
  end
end
