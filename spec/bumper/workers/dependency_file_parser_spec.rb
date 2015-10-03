require "spec_helper"
require "bumper/workers/dependency_file_parser"

RSpec.describe Workers::DependencyFileParser do
  subject(:worker) { described_class.new }
  let(:sqs_message) { double("sqs_message") }
  let(:body) do
    {
      "repo" => {
        "name" => "gocardless/bump",
        "language" => "ruby"
      },
      "dependency_files" => [
        { "name" => "Gemfile", "content" => fixture("Gemfile") },
        { "name" => "Gemfile.lock", "content" => fixture("Gemfile.lock") }
      ]
    }
  end

  describe "#perform" do
    subject(:perform) { worker.perform(sqs_message, body) }

    it "enqueues an UpdateChecker with the correct arguments" do
      expect(Workers::UpdateChecker).
        to receive(:perform_async).
        with(
          "repo" => body["repo"],
          "dependency_files" => body["dependency_files"],
          "dependency" => {
            "name" => "business",
            "version" => "1.4.0"
          })
      perform
    end
  end
end
