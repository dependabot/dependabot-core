require "spec_helper"
require "./app/workers/dependency_file_updater"

RSpec.describe Workers::DependencyFileUpdater do
  let(:worker) { described_class.new }
  let(:sqs_message) { double("sqs_message", delete: true) }
  let(:body) do
    {
      "repo" => {
        "name" => "gocardless/bump",
        "language" => "ruby"
      },
      "updated_dependency" => {
        "name" => "business",
        "version" => "1.5.0"
      },
      "dependency_files" => [
        { "name" => "Gemfile", "content" => fixture("Gemfile") },
        { "name" => "Gemfile.lock", "content" => fixture("Gemfile.lock") }
      ]
    }
  end

  describe "#perform" do
    subject(:perform) { worker.perform(sqs_message, body) }
    before do
      allow_any_instance_of(DependencyFileUpdaters::RubyDependencyFileUpdater).
        to receive(:updated_dependency_files).
        and_return([DependencyFile.new(name: "Gemfile", content: "xyz")])
    end

    it "enqueues a PullRequestCreator with the correct arguments" do
      expect(Workers::PullRequestCreator).
        to receive(:perform_async).
        with(
          "repo" => body["repo"],
          "updated_dependency" => body["updated_dependency"],
          "updated_dependency_files" => [{
            "name" => "Gemfile",
            "content" => "xyz"
          }])
      perform
    end

    context "if an error is raised" do
      before do
        allow(DependencyFileUpdaters::RubyDependencyFileUpdater).
          to receive(:new).
          and_raise("hell")
      end

      it "sends the error to sentry and doesn't raise" do
        expect(Raven).to receive(:capture_exception).and_call_original
        perform
      end
    end
  end
end
