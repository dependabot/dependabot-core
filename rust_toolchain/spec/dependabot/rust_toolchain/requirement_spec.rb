# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/rust_toolchain/requirement"

RSpec.describe Dependabot::RustToolchain::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }

  let(:requirement_string) { ">=1.72.0" }

  describe ".new" do
    it { is_expected.to be_a(described_class) }

    context "with a comma-separated string" do
      let(:requirement_string) { ">= 1.72.a, < 1.73" }

      it { is_expected.to eq(Gem::Requirement.new(">= 1.72.a", "< 1.73")) }
    end
  end
end
