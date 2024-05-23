# typed: false
# frozen_string_literal: true

require "sentry-ruby"
require "spec_helper"

require "dependabot/sentry/exception_sanitizer_processor"

RSpec.describe ExceptionSanitizer do
  subject { exception }

  let(:message) { "kaboom" }
  let(:exception) { instance_double(::Sentry::SingleExceptionInterface, value: message) }
  let(:event) { instance_double(::Sentry::ErrorEvent) }

  before do
    allow(exception).to receive(:value=)
    allow(event).to receive_message_chain("exception.values"). and_return([exception])
    allow(event).to receive(:is_a?). and_return(true)
    described_class.new.process(event, {})
  end

  it "does not filter messages by default" do
    expect(subject).to have_received(:value=).with(message).at_least(:once)
  end

  context "with exception containing Bearer token" do
    let(:message) { "Bearer SECRET_TOKEN is bad and you should feel bad" }

    it "filters sensitive messages" do
      expect(subject).to have_received(:value=).with("Bearer [FILTERED_AUTH_TOKEN] is bad and you should feel bad")
    end
  end

  context "with exception containing Authorization: header" do
    let(:message) { "Authorization: SECRET_TOKEN is bad" }

    it "filters sensitive messages" do
      expect(subject).to have_received(:value=).with("Authorization: [FILTERED_AUTH_TOKEN] is bad")
    end
  end

  context "with exception containing authorization value" do
    let(:message) { "authorization SECRET_TOKEN invalid" }

    it "filters sensitive messages" do
      expect(subject).to have_received(:value=).with("authorization [FILTERED_AUTH_TOKEN] invalid")
    end
  end

  context "with exception secret token without an indicator" do
    let(:message) { "SECRET_TOKEN is not filtered" }

    it "filters sensitive messages" do
      expect(subject).to have_received(:value=).with(message).at_least(:once)
    end
  end

  context "with api repo NWO" do
    let(:message) { "https://api.github.com/repos/foo/bar is bad" }

    it "filters repo name from an api request" do
      expect(subject).to have_received(:value=).with("https://api.github.com/repos/foo/[FILTERED_REPO] is bad")
    end
  end

  context "with regular repo NWO" do
    let(:message) { "https://github.com/foo/bar is bad" }

    it "filters repo name from an api request" do
      expect(subject).to have_received(:value=).with("https://github.com/foo/[FILTERED_REPO] is bad")
    end
  end

  context "with multiple repo NWO" do
    let(:message) do
      "https://api.github.com/repos/foo/bar is bad, " \
        "https://github.com/foo/baz is bad"
    end

    it "filters repo name from an api request" do
      expect(subject).to have_received(:value=).with(
        "https://api.github.com/repos/foo/[FILTERED_REPO] is bad, " \
        "https://github.com/foo/[FILTERED_REPO] is bad"
      )
    end
  end

  context "when docs.github.com URL included" do
    let(:message) { "https://api.github.com/repos/org/foo/contents/bar: 404 - Not Found // See: https://docs.github.com/rest/repos/contents#get-repository-content" }

    it "filters repo name from an api request" do
      expect(subject).to have_received(:value=)
        .with("https://api.github.com/repos/org/[FILTERED_REPO]/contents/bar: 404 - Not Found // See: https://docs.github.com/rest/repos/contents#get-repository-content")
    end
  end

  context "when docs.github.com URL included, and repo name includes 'repo'" do
    let(:message) { "https://api.github.com/repos/org/repo/contents/bar: 404 - Not Found // See: https://docs.github.com/rest/repos/contents#get-repository-content" }

    it "filters repo name from an api request" do
      expect(subject).to have_received(:value=)
        .with("https://api.github.com/repos/org/[FILTERED_REPO]/contents/bar: 404 - Not Found // See: https://docs.github.com/rest/repos/contents#get-repository-content")
    end
  end

  context "with SCP-style uri" do
    let(:message) { "git@github.com:foo/bar.git is bad" }

    it "filters repo name from an api request" do
      expect(subject).to have_received(:value=).with("git@github.com:foo/[FILTERED_REPO] is bad")
    end
  end
end
