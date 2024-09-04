# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/maven/version_parser"

RSpec.describe Dependabot::Maven::TokenBucket do
  subject(:token_bucket) { described_class.new(tokens: tokens, addition: addition) }

  let(:tokens) { [1, 2, 3] }
  let(:addition) { nil }

  describe "#to_a" do
    it "includes all tokens" do
      expect(token_bucket.to_a).to eq tokens
    end

    context "when the token bucket has additions" do
      let(:addition) { described_class.new(tokens: ["+", [181]]) }

      it "includes additions" do
        expect(token_bucket.to_a).to eq [1, 2, 3, ["+", [181]]]
      end
    end
  end

  describe "#<=>" do
    let(:first) { described_class.new(tokens: [1, 2]) }

    context "when equal" do
      let(:second) { described_class.new(tokens: [1, 2]) }

      it "returns the correct result" do
        expect(first <=> second).to eq(0)
      end
    end

    context "when different" do
      let(:second) { described_class.new(tokens: [1]) }

      it "returns the correct result" do
        expect(first <=> second).to eq(1)
        expect(second <=> first).to eq(-1)
      end
    end

    context "when the token bucket has additions" do
      let(:addition1) { described_class.new(tokens: [181]) }
      let(:addition2) { described_class.new(tokens: [182]) }

      let(:first) { described_class.new(tokens: tokens, addition: addition1) }
      let(:second) { described_class.new(tokens: tokens, addition: addition2) }

      it "returns the correct result" do
        expect(first <=> second).to eq(-1)
        expect(second <=> first).to eq(1)
      end
    end
  end

  describe "#compare_token_pair" do
    let(:tokens) do
      [
        [1, 1, 0],
        [2, 1, 1],
        [1, 2, -1],
        ["a", "a", 0],
        ["b", "a", 1],
        ["a", "b", -1],
        [1, "a", 1],
        ["a", 1, -1],
        [Dependabot::Maven::VersionParser::ALPHA, Dependabot::Maven::VersionParser::ALPHA, 0],
        [1, Dependabot::Maven::VersionParser::ALPHA, 1],
        ["a", Dependabot::Maven::VersionParser::ALPHA, 1],
        [nil, Dependabot::Maven::VersionParser::ALPHA, 1],
        [Dependabot::Maven::VersionParser::BETA, Dependabot::Maven::VersionParser::ALPHA, 1],
        [Dependabot::Maven::VersionParser::MILESTONE, Dependabot::Maven::VersionParser::BETA, 1],
        [Dependabot::Maven::VersionParser::RC, Dependabot::Maven::VersionParser::MILESTONE, 1],
        [Dependabot::Maven::VersionParser::SNAPSHOT, Dependabot::Maven::VersionParser::RC, 1],
        [Dependabot::Maven::VersionParser::SP, 0, 1],
        ["a", Dependabot::Maven::VersionParser::SP, 1]
      ]
    end

    it "returns the correct result" do
      tokens.each do |input|
        token1, token2, result = input
        expect(token_bucket.send(:compare_token_pair, token1, token2)).to eq result
      end
    end
  end
end
