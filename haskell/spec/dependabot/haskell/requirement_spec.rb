# frozen_string_literal: true

require "spec_helper"
require "dependabot/haskell/requirement"

RSpec.describe Dependabot::Haskell::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }
  let(:requirement_string) { ">=1.0.0" }

  describe ".new" do
    it { is_expected.to be_a(described_class) }

    context "with an intersection" do
      let(:requirement_string) { ">= 0.18.3 && < 0.20" }
      it { is_expected.to eq(Gem::Requirement.new(">= 0.18.3", "< 0.20")) }
    end

    context "with wildcard requirements" do
      let(:requirement_string) { "== 4.9.*" }
      it { is_expected.to eq(Gem::Requirement.new("= 4.9")) }
    end

    context "with requirement intersections/unions it just includes each of them" do
      let(:requirement_string) { "(>= 0.3      && < 0.4) || (>=0.4.1.0 && <0.6)" }
      it { is_expected.to eq(Gem::Requirement.new(">= 0.3", "< 0.4", ">= 0.4.1.0", "< 0.6")) }
    end

  end
end
