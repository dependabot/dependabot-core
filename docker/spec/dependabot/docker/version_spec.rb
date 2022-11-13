# frozen_string_literal: true

require "spec_helper"
require "dependabot/docker/version"

RSpec.describe Dependabot::Docker::Version do
  describe ".new" do
    it "sorts properly" do
      expect(described_class.new("2.4.2")).to be >= described_class.new("2.1.0")
      expect(described_class.new("2.4.2")).to be < described_class.new("2.4.3")
    end

    it "sorts properly when it uses underscores" do
      expect(described_class.new("11.0.16_8")).to be < described_class.new("11.0.16.1")
      expect(described_class.new("17.0.2_8")).to be > described_class.new("17.0.1_12")
    end
  end
end
