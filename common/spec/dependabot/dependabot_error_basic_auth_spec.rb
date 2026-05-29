# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/errors"

RSpec.describe Dependabot::DependabotError, "basic auth redaction" do
  subject(:error_message) { described_class.new(message).message }

  context "with an escaped at-sign in the http basic auth password" do
    let(:message) do
      "git://user:tok%40en@github.com error"
    end

    it { is_expected.to eq("git://github.com error") }
  end

  context "with an escaped slash in the http basic auth password" do
    let(:message) do
      "git://user:tok%2Fen@github.com error"
    end

    it { is_expected.to eq("git://github.com error") }
  end
end
