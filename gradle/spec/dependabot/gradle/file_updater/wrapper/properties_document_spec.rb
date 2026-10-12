# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/gradle/file_updater"

RSpec.describe Dependabot::Gradle::FileUpdater::Wrapper::PropertiesDocument do
  let(:content) do
    <<~PROPS
      # Managed by the platform team - do not edit by hand
      distributionBase=GRADLE_USER_HOME
      distributionPath=wrapper/dists
      distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14.2-bin.zip

      networkTimeout=10000
      retries=3
      retryBackOffMs=1000
      validateDistributionUrl=true
      myCompany.customKey=keep-me
    PROPS
  end

  describe ".parse and #to_s" do
    it "round-trips content byte-for-byte" do
      expect(described_class.parse(content).to_s).to eq(content)
    end
  end

  describe "#key? and #value_for" do
    subject(:document) { described_class.parse(content) }

    it "reads known keys" do
      expect(document.key?("networkTimeout")).to be(true)
      expect(document.value_for("networkTimeout")).to eq("10000")
      expect(document.value_for("retries")).to eq("3")
    end

    it "reads custom keys" do
      expect(document.value_for("myCompany.customKey")).to eq("keep-me")
    end

    it "reads escaped values verbatim" do
      expect(document.value_for("distributionUrl"))
        .to eq("https\\://services.gradle.org/distributions/gradle-8.14.2-bin.zip")
    end

    it "returns nil for unknown keys" do
      expect(document.key?("nope")).to be(false)
      expect(document.value_for("nope")).to be_nil
    end
  end

  describe "#upsert" do
    subject(:document) { described_class.parse(content) }

    it "replaces an existing value in place, preserving comments, order and other keys" do
      document.upsert(
        "distributionUrl",
        "https\\://services.gradle.org/distributions/gradle-9.0.0-bin.zip"
      )

      result = document.to_s
      expect(result).to include("distributionUrl=https\\://services.gradle.org/distributions/gradle-9.0.0-bin.zip")
      expect(result).to include("# Managed by the platform team - do not edit by hand")
      expect(result).to include("retries=3")
      expect(result).to include("myCompany.customKey=keep-me")
      expect(result).not_to include("gradle-8.14.2-bin.zip")
      # ordering preserved: distributionUrl still sits before networkTimeout
      expect(result.index("distributionUrl")).to be < result.index("networkTimeout")
    end

    it "appends a new key when it does not exist" do
      document.upsert("distributionSha256Sum", "abc123")
      expect(document.to_s).to include("distributionSha256Sum=abc123")
    end

    it "preserves a non-default separator when replacing" do
      doc = described_class.parse("networkTimeout : 5000\n")
      doc.upsert("networkTimeout", "10000")
      expect(doc.to_s).to eq("networkTimeout : 10000\n")
    end

    it "preserves leading indentation when replacing" do
      doc = described_class.parse("    distributionUrl=old\n")
      doc.upsert("distributionUrl", "new")
      expect(doc.to_s).to eq("    distributionUrl=new\n")
    end
  end
end
