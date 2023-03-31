# frozen_string_literal: true

require "spec_helper"
require "dependabot/docker/tag"

RSpec.describe Dependabot::Docker::Tag do
  describe "#same_but_more_precise?" do
    it "returns true when receiver is the same version as the parameter, just less precise, false otherwise" do
      expect(described_class.new("2.4").same_but_less_precise?(described_class.new("2.4.2"))).to be true
      expect(described_class.new("2.4").same_but_less_precise?(described_class.new("2.42"))).to be false
    end
  end
end
