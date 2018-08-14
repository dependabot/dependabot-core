# frozen_string_literal: true

require "spec_helper"
require "dependabot/utils/dotnet/requirement"
require "dependabot/utils/dotnet/version"

RSpec.describe Dependabot::Utils::Dotnet::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }
  let(:requirement_string) { ">=1.0.0" }

  describe ".new" do
    subject { described_class.new(requirement_string) }

    context "with only a *" do
      let(:requirement_string) { "*" }
      it { is_expected.to eq(described_class.new(">= 0")) }
    end

    context "with a *" do
      let(:requirement_string) { "1.*" }
      it { is_expected.to eq(described_class.new("~> 1.0")) }

      context "specifying pre-release versions" do
        let(:requirement_string) { "1.1-*" }
        it { is_expected.to eq(described_class.new("~> 1.1-a")) }
      end
    end
  end
end
