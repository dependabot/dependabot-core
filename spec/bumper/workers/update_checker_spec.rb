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
        { "name" => "Gemfile", "content" => fixture("Gemfile") },
        { "name" => "Gemfile.lock", "content" => fixture("Gemfile.lock") },
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

    it "enqueues a DependencyFileUpdater with the correct arguments" do
      expect(Workers::DependencyFileUpdater).
        to receive(:perform_async).
        with(
          "repo" => body["repo"],
          "dependency_files" => body["dependency_files"],
          "updated_dependency" => {
            "name" => "business",
            "version" => "1.5.0",
          })
      worker.perform(sqs_message, body)
    end
  end

  context "when no update is required" do
    before do
      allow_any_instance_of(UpdateCheckers::RubyUpdateChecker).
        to receive(:needs_update?).and_return(false)
    end

    it "doesn't write a message into the queue" do
      expect(Workers::DependencyFileUpdater).to_not receive(:perform_async)
      worker.perform(sqs_message, body)
    end
  end
end
