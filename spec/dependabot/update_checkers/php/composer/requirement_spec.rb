# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/php/composer/requirement"
require "dependabot/update_checkers/php/composer/version"

RSpec.describe Dependabot::UpdateCheckers::Php::Composer::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }
  let(:requirement_string) { ">=1.0.0" }

  describe ".new" do
    it { is_expected.to be_a(described_class) }

    context "with a stability constraint" do
      let(:requirement_string) { ">=1.0.0@dev" }
      it { is_expected.to eq(described_class.new(">=1.0.0")) }
    end

    context "with an alias" do
      let(:requirement_string) { ">=whatever as 1.0.0" }
      it { is_expected.to eq(described_class.new(">=1.0.0")) }
    end
  end
end
