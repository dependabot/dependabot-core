# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dotnet_sdk/requirement"

RSpec.describe Dependabot::DotnetSdk::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }

  let(:requirement_string) { ">=9.0.100" }

  describe ".new" do
    it { is_expected.to be_a(described_class) }

    context "with a comma-separated string" do
      let(:requirement_string) { ">= 9.1.a, < 10" }

      it { is_expected.to eq(Gem::Requirement.new(">= 9.1.a", "< 10")) }
    end
  end
end
