require "spec_helper"
require "bumper/workers/update_checker"

RSpec.describe Workers::UpdateChecker do
  let(:worker) { described_class.new }
  let(:sqs_message) { double("sqs_message") }
  let(:body) do
    {
      "repo" => {
        "name" => "gocardless/bump",
        "language" => "ruby",
      },
      "dependency" => {
        "name" => "business",
        "version" => "1.4.0",
      },
      "dependency_files" => [
        { "name" => "Gemfile", "content" => "xyz" },
        { "name" => "Gemfile.lock", "content" => "xyz" },
      ]
    }
  end

  context "when an update is required" do
    before do
      allow_any_instance_of(UpdateCheckers::RubyUpdateChecker).
        to receive(:needs_update?).and_return(true)
      allow_any_instance_of(UpdateCheckers::RubyUpdateChecker).
        to receive(:latest_version).and_return("1.5.0")
    end

    it "writes a message into the queue" do
      expect(worker).to receive(:update_dependency)
      worker.perform(sqs_message, body)
    end
  end

  context "when no update is required" do
    before do
      allow_any_instance_of(UpdateCheckers::RubyUpdateChecker).
        to receive(:needs_update?).and_return(false)
    end

    it "doesn't write a message into the queue" do
      expect(worker).to_not receive(:send_update_notification)
      worker.perform(sqs_message, body)
    end
  end
end
