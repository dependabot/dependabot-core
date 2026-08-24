# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/swift/file_updater/requirement_replacer"

RSpec.describe Dependabot::Swift::FileUpdater::RequirementReplacer do
  subject(:replacer) do
    described_class.new(
      content: content,
      declaration: declaration,
      old_requirement: old_requirement,
      new_requirement: new_requirement
    )
  end

  let(:url) { "https://github.com/ordo-one/benchmark" }
  let(:content) { "let package = Package(\n  dependencies: [\n    #{declaration}\n  ]\n)\n" }

  describe "#updated_content" do
    context "with a multi-line declaration where the requirement is followed by another argument" do
      let(:declaration) do
        ".package(\n" \
          "      url: \"#{url}\",\n" \
          "      #{old_requirement}\n" \
          "      traits: []\n" \
          "    )"
      end
      # The parser captures the trailing comma as part of the requirement string.
      let(:old_requirement) { ".upToNextMajor(from: \"1.30.0\")," }

      context "when the new requirement does not carry the trailing separator" do
        let(:new_requirement) { "\"1.30.0\"...\"1.36.2\"" }

        it "preserves the comma separating the requirement from the next argument" do
          expect(replacer.updated_content).to include("\"1.30.0\"...\"1.36.2\",\n")
          expect(replacer.updated_content).to include("traits: []")
        end
      end

      context "when the new requirement already carries the trailing separator" do
        let(:new_requirement) { ".upToNextMajor(from: \"1.36.2\")," }

        it "does not duplicate the trailing comma" do
          expect(replacer.updated_content).to include(".upToNextMajor(from: \"1.36.2\"),\n")
          expect(replacer.updated_content).not_to include(",,")
        end
      end
    end

    context "with a multi-line declaration where the requirement line ends with an inline comment" do
      let(:declaration) do
        ".package(\n" \
          "      url: \"#{url}\",\n" \
          "      #{old_requirement}\n" \
          "      traits: []\n" \
          "    )"
      end
      # The parser captures the trailing comma and comment as part of the requirement string.
      let(:old_requirement) { ".upToNextMajor(from: \"1.30.0\"), // keep this" }

      context "when the new requirement does not carry the trailing separator" do
        let(:new_requirement) { "\"1.30.0\"...\"1.36.2\"" }

        it "preserves the comma and comment before the next argument" do
          expect(replacer.updated_content).to include("\"1.30.0\"...\"1.36.2\", // keep this\n")
          expect(replacer.updated_content).to include("traits: []")
        end
      end

      context "when the new requirement already carries the trailing comma and comment" do
        let(:new_requirement) { ".upToNextMajor(from: \"1.36.2\"), // keep this" }

        it "does not duplicate the suffix" do
          expect(replacer.updated_content).to include(".upToNextMajor(from: \"1.36.2\"), // keep this\n")
          expect(replacer.updated_content).not_to include("// keep this // keep this")
        end
      end
    end

    context "with a single-line declaration where the requirement has no trailing separator" do
      let(:declaration) { ".package(url: \"#{url}\", from: \"1.0.0\")" }
      let(:old_requirement) { "from: \"1.0.0\"" }
      let(:new_requirement) { "from: \"1.1.0\"" }

      it "replaces the requirement without adding a separator" do
        expect(replacer.updated_content).to include(".package(url: \"#{url}\", from: \"1.1.0\")")
      end
    end
  end
end
