# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bundler/requirement"

RSpec.describe Dependabot::Bundler::Requirement do
  extend T::Sig

  sig { returns(Dependabot::Bundler::Requirement) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  subject(:requirement) { described_class.new(requirement_string) }

  sig { returns(String) }
  let(:requirement_string) { ">=1.0.0" }

  describe ".new" do
    it { is_expected.to be_a(described_class) }

    context "with a comma-separated string" do
      sig { returns(String) }
      let(:requirement_string) { "~> 4.2.5, >= 4.2.5.1" }

      it { is_expected.to eq(Gem::Requirement.new("~> 4.2.5", ">= 4.2.5.1")) }
    end
  end
end
