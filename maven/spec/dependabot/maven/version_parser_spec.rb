# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/maven/version_parser"

RSpec.describe Dependabot::Maven::VersionParser do
  subject(:version) { described_class.parse(version_string) }

  describe ".parse" do
    let(:valid_versions) do
      [
        ["1.2.3", [1, 2, 3]],
        ["1-z", [1, ["z"]]],
        ["1z", [1, ["z"]]],
        ["1-z.1", [1, ["z", 1]]],
        ["1-z-1", [1, ["z", [1]]]],
        ["1-z1", [1, ["z", [1]]]],
        ["1-z-1.2", [1, ["z", [1, 2]]]],
        ["1-z-1-2", [1, ["z", [1, [2]]]]],
        ["1-z-1-2.3y", [1, ["z", [1, [2, 3, ["y"]]]]]],
        ["1ga1", [1, [[1]]]],
        ["1-ga-2", [1, [[2]]]],
        ["1_", [1, ["_"]]],
        ["1__", [1, ["__"]]],
        ["1__-", [1, ["__"]]],
        ["1_1", [1, ["_", [1]]]],
        ["1_a", [1, ["_a"]]],
        ["9+181-r4173-14", [9, ["+", [181, ["r", [4173, [14]]]]]]],
        ["9-+a", [9, ["+a"]]]
      ]
    end

    context "with a valid version" do
      it "returns the correct array" do
        valid_versions.each do |input|
          version, result = input
          expect(described_class.parse(version)).to eq(result)
        end
      end
    end
  end
end
