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
end
