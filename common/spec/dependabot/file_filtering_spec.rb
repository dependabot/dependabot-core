# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/file_filtering"

RSpec.describe Dependabot::FileFiltering do
  describe ".exclude_path?" do
    subject(:exclude_path) { described_class.exclude_path?(path, exclude_patterns) }

    context "with nil exclude_patterns" do
      let(:path) { "src/package.json" }
      let(:exclude_patterns) { nil }

      it { is_expected.to be(false) }
    end

    context "with empty exclude_patterns" do
      let(:path) { "src/package.json" }
      let(:exclude_patterns) { [] }

      it { is_expected.to be(false) }
    end

    context "with exact path matching" do
      let(:path) { "frontend/package.json" }
      let(:exclude_patterns) { ["frontend/package.json"] }

      it { is_expected.to be(true) }
    end

    context "with directory prefix matching" do
      let(:path) { "frontend/src/package.json" }
      let(:exclude_patterns) { ["frontend/"] }

      it { is_expected.to be(true) }

      context "when path is not inside directory" do
        let(:path) { "backend/src/package.json" }
        let(:exclude_patterns) { ["frontend/"] }

        it { is_expected.to be(false) }
      end
    end

    context "with recursive patterns (ending with /**)" do
      let(:path) { "src/components/button/package.json" }
      let(:exclude_patterns) { ["src/**"] }

      it { is_expected.to be(true) }

      context "with exact match of base pattern" do
        let(:path) { "src/package.json" }
        let(:exclude_patterns) { ["src/**"] }

        it { is_expected.to be(true) }
      end

      context "when path is outside recursive directory" do
        let(:path) { "lib/package.json" }
        let(:exclude_patterns) { ["src/**"] }

        it { is_expected.to be(false) }
      end
    end

    context "with glob pattern matching" do
      let(:path) { "src/frontend/package.json" }
      let(:exclude_patterns) { ["**/frontend/**"] }

      it { is_expected.to be(true) }

      context "with simple wildcard" do
        let(:path) { "package-lock.json" }
        let(:exclude_patterns) { ["*.json"] }

        it { is_expected.to be(true) }
      end

      context "with character class patterns" do
        let(:path) { "test1/package.json" }
        let(:exclude_patterns) { ["test[0-9]/package.json"] }

        it { is_expected.to be(true) }
      end

      context "when glob doesn't match" do
        let(:path) { "src/backend/package.json" }
        let(:exclude_patterns) { ["**/frontend/**"] }

        it { is_expected.to be(false) }
      end
    end

    context "with multiple exclude patterns" do
      let(:path) { "frontend/package.json" }
      let(:exclude_patterns) { ["backend/", "docs/", "frontend/"] }

      it "returns true if any pattern matches" do
        expect(exclude_path).to be(true)
      end

      context "when no patterns match" do
        let(:path) { "src/package.json" }
        let(:exclude_patterns) { ["backend/", "docs/", "frontend/"] }

        it { is_expected.to be(false) }
      end
    end

    context "with path normalization" do
      context "with leading slashes" do
        let(:path) { "/src/package.json" }
        let(:exclude_patterns) { ["src/"] }

        it "normalizes and matches" do
          expect(exclude_path).to be(true)
        end
      end

      context "with relative path components" do
        let(:path) { "src/../frontend/package.json" }
        let(:exclude_patterns) { ["frontend/"] }

        it "normalizes and matches" do
          expect(exclude_path).to be(true)
        end
      end

      context "with trailing slashes in patterns" do
        let(:path) { "frontend/package.json" }
        let(:exclude_patterns) { ["frontend//"] }

        it "normalizes pattern and matches" do
          expect(exclude_path).to be(true)
        end
      end
    end

    context "with edge cases" do
      context "with empty path" do
        let(:path) { "" }
        let(:exclude_patterns) { ["src/"] }

        it { is_expected.to be(false) }
      end

      context "with dot files" do
        let(:path) { ".github/workflows/ci.yml" }
        let(:exclude_patterns) { [".github/**"] }

        it { is_expected.to be(true) }
      end
    end
  end
end
