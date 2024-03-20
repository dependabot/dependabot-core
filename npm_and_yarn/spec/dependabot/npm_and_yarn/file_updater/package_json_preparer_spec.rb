# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_updater/package_json_preparer"

RSpec.describe Dependabot::NpmAndYarn::FileUpdater::PackageJsonPreparer do
  describe "#prepared_content" do
    it "does not craash when finding null dependencies" do
      original_content = fixture("projects", "generic", "null_deps", "package.json")

      preparer = described_class.new(package_json_content: original_content)

      expect(preparer.prepared_content).to eq(original_content)
    end
  end
end
