# frozen_string_literal: true
require "sentry-ruby"
require "dependabot/sentry"
require "spec_helper"

RSpec.describe ExceptionSanitizer do
  let(:exception_message) { "kaboom" }
  let(:fake_exception) { StandardError.new(exception_message) }
  let(:event) do
    {
      # TODO: Sentry Events are a custom object, not a hash... probably need to change this
      # They have a lot of fields, but we only care about the internal exception interface. I hate mocking what
      # we don't own, but creating a real Sentry Event requires fake config etc. And this should be a pretty stable interface.
      environment: "development",
      message: "",
      extra: {},
      exception: {
        values: [
          Sentry::SingleExceptionInterface.new(exception: :fake_exception)
        ]
      }
    }
  end
  let(:hint) { { :exception => :fake_exception, :exception_message => nil } }

  it "does not filter messages by default" do
    expect(sanitized_message(event, hint)).to eq(exception_message)
  end

  context "with exception containing Bearer token" do
    let(:exception_message) { "Bearer SECRET_TOKEN is bad and you should feel bad" }

    it "filters sensitive messages" do
      expect(sanitized_message(event, hint)).to eq(
        "Bearer [FILTERED_AUTH_TOKEN] is bad and you should feel bad"
      )
    end
  end

  context "with exception containing Authorization: header" do
    let(:exception_message) { "Authorization: SECRET_TOKEN is bad" }

    it "filters sensitive messages" do
      expect(sanitized_message(event, hint)).to eq(
        "Authorization: [FILTERED_AUTH_TOKEN] is bad"
      )
    end
  end

  context "with exception containing authorization value" do
    let(:exception_message) { "authorization SECRET_TOKEN invalid" }

    it "filters sensitive messages" do
      expect(sanitized_message(event, hint)).to eq(
        "authorization [FILTERED_AUTH_TOKEN] invalid"
      )
    end
  end

  context "with exception secret token without an indicator" do
    let(:exception_message) { "SECRET_TOKEN is not filtered" }

    it "filters sensitive messages" do
      expect(sanitized_message(event, hint)).to eq("SECRET_TOKEN is not filtered")
    end
  end

  context "with api repo NWO" do
    let(:exception_message) { "https://api.github.com/repos/foo/bar is bad" }

    it "filters repo name from an api request" do
      expect(sanitized_message(event, hint)).to eq(
        "https://api.github.com/repos/foo/[FILTERED_REPO] is bad"
      )
    end
  end

  context "with regular repo NWO" do
    let(:exception_message) { "https://github.com/foo/bar is bad" }

    it "filters repo name from an api request" do
      expect(sanitized_message(event, hint)).to eq(
        "https://github.com/foo/[FILTERED_REPO] is bad"
      )
    end
  end

  context "with multiple repo NWO" do
    let(:exception_message) do
      "https://api.github.com/repos/foo/bar is bad, " \
        "https://github.com/foo/baz is bad"
    end

    it "filters repo name from an api request" do
      expect(sanitized_message(event, hint)).to eq(
        "https://api.github.com/repos/foo/[FILTERED_REPO] is bad, " \
        "https://github.com/foo/[FILTERED_REPO] is bad"
      )
    end
  end

  private

  def sanitized_message(event, hint)
    sanitized_event = ExceptionSanitizer.new.sanitize_sentry_exception_event(event, hint)
    # TODO this may need changing since the event is now an object not a hash I think??
    debugger
    sanitized_event[:exception][:values].first[:value]
  end
end
