# typed: false
# frozen_string_literal: true

require "sentry-ruby"
require "spec_helper"

require "dependabot/errors"
require "dependabot/sentry/sentry_context_processor"

RSpec.describe SentryContext do
  let(:sentry_context) { { foo: "bar" } }
  let(:exception) { double(::Dependabot::DependabotError, sentry_context: sentry_context) }
  let(:hint) { { exception: exception } }
  let(:event) { instance_double(::Sentry::ErrorEvent) }

  subject { event }

  before do
    allow(event).to receive(:send)
    described_class.new.process(event, hint)
  end

  it "adds context to the event" do
    is_expected.to have_received(:send).with("foo=", "bar")
  end

  context "without an exception" do
    let(:exception) { nil }

    it "does not add context" do
      is_expected.not_to have_received(:send)
    end
  end

  context "without sentry_context" do
    let(:sentry_context) { nil }

    it "does not add context" do
      is_expected.not_to have_received(:send)
    end
  end
end
