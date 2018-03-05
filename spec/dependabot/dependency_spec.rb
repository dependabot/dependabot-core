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

  describe "#production?" do
    subject(:dependency) { described_class.new(dependency_args).production? }

    let(:dependency_args) do
      {
        name: "dep",
        requirements: [
          { file: "a.rb", requirement: "1", groups: groups, source: nil }
        ],
        package_manager: package_manager
      }
    end
    let(:groups) { [] }
    let(:package_manager) { "bundler" }

    context "for a requirement that isn't top-level" do
      let(:dependency_args) do
        { name: "dep", requirements: [], package_manager: package_manager }
      end

      it { is_expected.to be_nil }
    end

    %w(submodules docker maven pip).each do |manager|
      context "for a #{manager} dependency" do
        let(:package_manager) { "manager" }

        it { is_expected.to eq(true) }
      end
    end
  end
end
