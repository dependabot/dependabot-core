# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun"

RSpec.describe Dependabot::Javascript::Shared::FileUpdater::PackageJsonPreparer do
  describe "#prepared_content" do
    it "does not craash when finding null dependencies" do
      original_content = fixture("projects", "javascript", "null_deps", "package.json")

      preparer = described_class.new(package_json_content: original_content)

      expect(preparer.prepared_content).to eq(original_content)
    end
  end
end
