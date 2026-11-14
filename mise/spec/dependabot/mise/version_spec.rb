# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/mise/version"

RSpec.describe Dependabot::Mise::Version do
  describe "#prerelease?" do
    %w(27.3.2 1.18.4-otp-27 1.2.3-linux-x64 1.2.3-alpine 3.15.0.post1).each do |version|
      it "returns false for #{version}" do
        expect(described_class.new(version)).not_to be_prerelease
      end
    end

    %w(
      28.0-rc1
      4.1.0-preview1
      3.16-dev
      3.16.0.dev0
      3.15.0a1
      3.15.0b2
      3.15.0rc1
      8.5.9RC1
      27.0.0-alpha.0.1.0
      1.0.0.beta.1
      1.0.0-canary.1
      1.0.0-nightly.20261114
      1.19.0-rc.1-otp-27
      1.19.0-otp-27-rc1
    ).each do |version|
      it "returns true for #{version}" do
        expect(described_class.new(version)).to be_prerelease
      end
    end
  end
end
