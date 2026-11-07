# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/github_actions/runner_label"

RSpec.describe Dependabot::GithubActions::RunnerLabel do
  describe ".parse" do
    {
      "ubuntu-24.04" => %w(ubuntu 24.04),
      "ubuntu-22.04-arm" => %w(ubuntu-arm 22.04),
      "windows-2022" => %w(windows 2022),
      "macos-15" => %w(macos 15),
      "macos-15-xlarge" => %w(macos-xlarge 15),
      "macos-14-large" => %w(macos-large 14),
      "macos-15-intel" => %w(macos-intel 15)
    }.each do |label, (family, version)|
      it "reads #{label} as #{family} #{version}" do
        runner = described_class.parse(label)

        expect([runner.family, runner.version]).to eq([family, version])
      end
    end

    %w(
      ubuntu-latest
      macos-latest-large
      ubuntu-slim
      windows-11-arm
      windows-2025-vs2026
      ubuntu-22.04-gpu
      my-ubuntu-22.04
      ubuntu-24
      windows-11
      macos-13
      ubuntu-20.04
    ).each do |label|
      it "does not read #{label} as a versioned hosted runner" do
        expect(described_class.parse(label)).to be_nil
      end
    end
  end

  describe "#with_version" do
    it "keeps the family suffix after the new version" do
      expect(described_class.parse("ubuntu-22.04-arm").with_version("26.04")).to eq("ubuntu-26.04-arm")
    end
  end
end
