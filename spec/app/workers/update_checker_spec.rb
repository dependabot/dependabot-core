require "spec_helper"
require "./app/workers/update_checker"

RSpec.describe Workers::UpdateChecker do
  let(:worker) { described_class.new }
  let(:sqs_message) { double("sqs_message") }
  let(:body) do
    {
      "repo" => {
        "name" => "gocardless/bump",
        "language" => "ruby"
      },
      "dependency" => {
        "name" => "business",
        "version" => "1.4.0"
      },
      "dependency_files" => [
        { "name" => "Gemfile", "content" => fixture("Gemfile") },
        { "name" => "Gemfile.lock", "content" => fixture("Gemfile.lock") }
      ]
    }
  end

  describe "#perform" do
    subject(:perform) { worker.perform(sqs_message, body) }

    context "when an update is required" do
      before do
        allow_any_instance_of(UpdateCheckers::Ruby).
          to receive(:needs_update?).and_return(true)
        allow_any_instance_of(UpdateCheckers::Ruby).
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
              "version" => "1.5.0"
            })
        perform
      end
    end

    context "when no update is required" do
      before do
        allow_any_instance_of(UpdateCheckers::Ruby).
          to receive(:needs_update?).and_return(false)
      end

      it "doesn't write a message into the queue" do
        expect(Workers::DependencyFileUpdater).to_not receive(:publish)
        perform
      end
    end

    context "if an error is raised" do
      before { allow(UpdateCheckers::Ruby).to receive(:new).and_raise("hell") }

      it "still raises, but also sends the error to sentry" do
        expect(Raven).to receive(:capture_exception).and_call_original
        expect { perform }.to raise_error("hell")
      end
    end
  end
end
