# frozen_string_literal: true

require "spec_helper"
require "dependabot/puppet/requirement"
require "dependabot/puppet/version"

RSpec.describe Dependabot::Puppet::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }
  let(:requirement_string) { "1.0.0" }

  describe ".new" do
    it { is_expected.to be_a(described_class) }
  end
end
