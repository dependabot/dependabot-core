# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/gradle/file_updater"
require "dependabot/gradle/version"

RSpec.describe Dependabot::Gradle::FileUpdater::Wrapper::GradleVersionCapabilities do
  describe ".supports?" do
    def version(str)
      Dependabot::Gradle::Version.new(str)
    end

    it "gates --retries / --retry-back-off-ms behind 9.5.0" do
      expect(described_class.supports?("retries", version("9.5.0"))).to be(true)
      expect(described_class.supports?("retries", version("9.4.0"))).to be(false)
      expect(described_class.supports?("retry-back-off-ms", version("9.5.1"))).to be(true)
      expect(described_class.supports?("retry-back-off-ms", version("9.0.0"))).to be(false)
    end

    it "gates --network-timeout behind 7.6" do
      expect(described_class.supports?("network-timeout", version("7.6"))).to be(true)
      expect(described_class.supports?("network-timeout", version("7.5"))).to be(false)
    end

    it "gates --validate-url behind 8.2" do
      expect(described_class.supports?("validate-url", version("8.2"))).to be(true)
      expect(described_class.supports?("validate-url", version("8.1"))).to be(false)
    end

    it "refuses gated options when the executing version is unknown" do
      expect(described_class.supports?("retries", nil)).to be(false)
      expect(described_class.supports?("network-timeout", nil)).to be(false)
    end

    it "allows ungated options regardless of version" do
      expect(described_class.supports?("some-future-option", nil)).to be(true)
      expect(described_class.supports?("some-future-option", version("1.0"))).to be(true)
    end
  end
end
