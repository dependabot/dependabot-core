# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/peer_dependency_conflict"

RSpec.describe Dependabot::UpdateCheckers::PeerDependencyConflict do
  describe ".from_captures" do
    subject(:conflict) { described_class.from_captures(captures) }

    let(:captures) { { "required_dep" => 'react@"^16.0.0 || ^17.0.0"', "requiring_dep" => "react-dom@16.0.0" } }

    it "retains the existing name and quoted-range normalization" do
      expect(conflict).to have_attributes(
        requirement_name: "react",
        requirement_version: "^16.0.0 || ^17.0.0",
        requiring_dep_name: "react-dom"
      )
    end

    context "with scoped names" do
      let(:captures) { { "required_dep" => "@scope/peer@>=1 <2", "requiring_dep" => "@scope/parent@1.2.0" } }

      it "strips only the version suffix" do
        expect(conflict).to have_attributes(
          requirement_name: "@scope/peer",
          requirement_version: ">=1 <2",
          requiring_dep_name: "@scope/parent"
        )
      end
    end

    context "with unversioned diagnostic names" do
      let(:captures) { { "required_dep" => "jest", "requiring_dep" => "ts-jest", "info_hash" => "p8d618" } }

      it "preserves the legacy normalization rather than inventing a range" do
        expect(conflict).to have_attributes(
          requirement_name: "jest",
          requirement_version: "jest",
          requiring_dep_name: "ts-jest"
        )
      end
    end

    context "with empty diagnostic fields" do
      let(:captures) { { "required_dep" => "", "requiring_dep" => "" } }

      it "preserves the nil range" do
        expect(conflict).to have_attributes(requirement_name: "", requirement_version: nil, requiring_dep_name: "")
      end
    end

    [
      {},
      { "required_dep" => nil, "requiring_dep" => "parent@1" },
      { "required_dep" => "peer@1", "requiring_dep" => nil }
    ].each do |value|
      context "with incomplete captures #{value.inspect}" do
        let(:captures) { value }

        it "does not create an empty conflict record" do
          expect(conflict).to be_nil
        end
      end
    end
  end

  describe "#same_dependencies?" do
    subject(:conflict) do
      described_class.new(requirement_name: "react", requirement_version: "^16", requiring_dep_name: "react-dom")
    end

    it "ignores differences in the version requirement" do
      previous = described_class.new(
        requirement_name: "react",
        requirement_version: "^15",
        requiring_dep_name: "react-dom"
      )
      expect(conflict.same_dependencies?(previous)).to be(true)
    end

    it "keeps different requiring dependencies distinct" do
      other = described_class.new(
        requirement_name: "react",
        requirement_version: "^16",
        requiring_dep_name: "react-modal"
      )
      expect(conflict.same_dependencies?(other)).to be(false)
    end

    it "keeps different required dependencies distinct" do
      other = described_class.new(requirement_name: "vue", requirement_version: "^16", requiring_dep_name: "react-dom")
      expect(conflict.same_dependencies?(other)).to be(false)
    end
  end
end
