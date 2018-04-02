# frozen_string_literal: true

require "spec_helper"
require "dependabot/utils/ruby/requirement"

RSpec.describe Dependabot::Utils::Ruby::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }
  let(:requirement_string) { ">=1.0.0" }

  describe ".new" do
    it { is_expected.to be_a(described_class) }

    context "with a comma-separated string" do
      let(:requirement_string) { "~> 4.2.5, >= 4.2.5.1" }
      it { is_expected.to eq(Gem::Requirement.new("~> 4.2.5", ">= 4.2.5.1")) }
    end
  end
end
