# typed: false
# frozen_string_literal: true

require "sentry-ruby"
require "spec_helper"

require "dependabot/errors"
require "dependabot/sentry/sentry_context_processor"

RSpec.describe SentryContext do
  subject { event }

  let(:sentry_context) { { foo: "bar" } }
  let(:exception) do
    context = sentry_context
    Class.new(StandardError) do
      include Dependabot::HasSentryContext

      define_method(:sentry_context) { context }
    end.new
  end
  let(:hint) { { exception: exception } }
  let(:event) { instance_double(::Sentry::ErrorEvent) }

  before do
    allow(event).to receive(:send)
    described_class.new.process(event, hint)
  end

  it "adds context to the event" do
    expect(event).to have_received(:send).with(:foo=, "bar")
  end

  context "without an exception" do
    let(:exception) { nil }

    it "does not add context" do
      expect(event).not_to have_received(:send)
    end
  end

  context "with empty sentry_context" do
    let(:sentry_context) { {} }

    it "does not add context" do
      expect(event).not_to have_received(:send)
    end
  end
end
