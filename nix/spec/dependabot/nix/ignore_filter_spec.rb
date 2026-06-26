# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nix/ignore_filter"

RSpec.describe Dependabot::Nix::IgnoreFilter do
  subject(:filter) { described_class.new(ignored_versions) }

  describe "#ignored?" do
    context "with no ignore conditions" do
      let(:ignored_versions) { [] }

      it "treats every version as allowed" do
        expect(filter.ignored?("26.05")).to be(false)
      end
    end

    context "with a matching equality condition" do
      let(:ignored_versions) { ["= 26.05"] }

      it "ignores the matching version" do
        expect(filter.ignored?("26.05")).to be(true)
      end

      it "allows non-matching versions" do
        expect(filter.ignored?("25.05")).to be(false)
      end
    end

    context "with a range condition" do
      let(:ignored_versions) { [">= 24"] }

      it "ignores versions in the range" do
        expect(filter.ignored?("24.11")).to be(true)
      end

      it "allows versions below the range" do
        expect(filter.ignored?("23.11")).to be(false)
      end
    end

    context "with an invalid condition" do
      let(:ignored_versions) { ["not a requirement"] }

      it "skips the bad condition and allows the version" do
        expect(filter.ignored?("26.05")).to be(false)
      end
    end

    context "with a nil version" do
      let(:ignored_versions) { ["= 26.05"] }

      it "returns false" do
        expect(filter.ignored?(nil)).to be(false)
      end
    end
  end
end
