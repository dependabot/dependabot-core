# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"

RSpec.describe Dependabot::Dependency do
  describe ".new" do
    subject(:dependency) { described_class.new(args) }

    let(:args) do
      {
        name: "dep",
        requirements: [
          {
            "file" => "a.rb",
            "requirement" => ">= 0",
            "groups" => [],
            source: nil
          }
        ],
        package_manager: "bundler"
      }
    end

    it "converts string keys to symbols" do
      expect(dependency.requirements).
        to eq([{ file: "a.rb", requirement: ">= 0", groups: [], source: nil }])
    end
  end

  describe "#==" do
    let(:args) do
      {
        name: "dep",
        requirements: [
          { file: "a.rb", requirement: "1", groups: [], source: nil }
        ],
        package_manager: "bundler"
      }
    end

    context "when two dependencies are equal" do
      let(:dependency1) { described_class.new(args) }
      let(:dependency2) { described_class.new(args) }

      specify { expect(dependency1).to eq(dependency2) }
    end

    context "when two dependencies are not equal" do
      let(:dependency1) { described_class.new(args) }
      let(:dependency2) { described_class.new(args.merge(name: "dep2")) }

      specify { expect(dependency1).to_not eq(dependency2) }
    end
  end
end
