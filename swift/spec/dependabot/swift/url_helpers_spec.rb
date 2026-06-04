# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/swift/url_helpers"

RSpec.describe Dependabot::Swift::UrlHelpers do
  describe ".normalize_name" do
    it "strips the scheme" do
      expect(described_class.normalize_name("https://github.com/user/repo")).to eq("github.com/user/repo")
    end

    it "strips the www. prefix" do
      expect(described_class.normalize_name("https://www.github.com/user/repo")).to eq("github.com/user/repo")
    end

    it "strips the .git suffix" do
      expect(described_class.normalize_name("https://github.com/user/repo.git")).to eq("github.com/user/repo")
    end

    it "strips a trailing slash" do
      expect(described_class.normalize_name("https://github.com/user/repo/")).to eq("github.com/user/repo")
    end

    it "strips a trailing slash followed by .git" do
      expect(described_class.normalize_name("https://github.com/user/repo.git/")).to eq("github.com/user/repo")
    end

    it "lowercases the result" do
      expect(described_class.normalize_name("https://github.com/User/Repo")).to eq("github.com/user/repo")
    end

    it "handles URLs without a trailing slash or .git" do
      expect(described_class.normalize_name("https://github.com/getsentry/sentry-cocoa"))
        .to eq("github.com/getsentry/sentry-cocoa")
    end

    it "strips the trailing slash from sentry-cocoa URL (the reported bug)" do
      expect(described_class.normalize_name("https://github.com/getsentry/sentry-cocoa/"))
        .to eq("github.com/getsentry/sentry-cocoa")
    end

    it "strips trailing slash and .git in fallback path when URI parsing fails" do
      expect(described_class.normalize_name("not a uri.git/")).to eq("not a uri")
    end
  end
end
