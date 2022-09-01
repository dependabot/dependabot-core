# frozen_string_literal: true

require "dependabot/sentry"
require "spec_helper"

RSpec.describe ExceptionSanitizer do
  let(:message) { "kaboom" }
  let(:data) do
    {
      environment: "default",
      extra: {},
      exception: {
        values: [
          { type: "StandardError", value: message }
        ]
      }
    }
  end

  it "does not filter messages by default" do
    expect(sanitized_message(data)).to eq(message)
  end

  context "with exception containing Bearer token" do
    let(:message) { "Bearer SECRET_TOKEN is bad and you should feel bad" }

    it "filters sensitive messages" do
      expect(sanitized_message(data)).to eq(
        "Bearer [FILTERED_AUTH_TOKEN] is bad and you should feel bad"
      )
    end
  end

  context "with exception containing Authorization: header" do
    let(:message) { "Authorization: SECRET_TOKEN is bad" }

    it "filters sensitive messages" do
      expect(sanitized_message(data)).to eq(
        "Authorization: [FILTERED_AUTH_TOKEN] is bad"
      )
    end
  end

  context "with exception containing authorization value" do
    let(:message) { "authorization SECRET_TOKEN invalid" }

    it "filters sensitive messages" do
      expect(sanitized_message(data)).to eq(
        "authorization [FILTERED_AUTH_TOKEN] invalid"
      )
    end
  end

  context "with exception secret token without an indicator" do
    let(:message) { "SECRET_TOKEN is not filtered" }

    it "filters sensitive messages" do
      expect(sanitized_message(data)).to eq("SECRET_TOKEN is not filtered")
    end
  end

  context "with api repo NWO" do
    let(:message) { "https://api.github.com/repos/foo/bar is bad" }

    it "filters repo name from an api request" do
      expect(sanitized_message(data)).to eq(
        "https://api.github.com/repos/foo/[FILTERED_REPO] is bad"
      )
    end
  end

  context "with regular repo NWO" do
    let(:message) { "https://github.com/foo/bar is bad" }

    it "filters repo name from an api request" do
      expect(sanitized_message(data)).to eq(
        "https://github.com/foo/[FILTERED_REPO] is bad"
      )
    end
  end

  context "with multiple repo NWO" do
    let(:message) do
      "https://api.github.com/repos/foo/bar is bad, " \
        "https://github.com/foo/baz is bad"
    end

    it "filters repo name from an api request" do
      expect(sanitized_message(data)).to eq(
        "https://api.github.com/repos/foo/[FILTERED_REPO] is bad, " \
        "https://github.com/foo/[FILTERED_REPO] is bad"
      )
    end
  end

  private

  def sanitized_message(data)
    filtered = ExceptionSanitizer.new.process(data)
    filtered[:exception][:values].first[:value]
  end
end
