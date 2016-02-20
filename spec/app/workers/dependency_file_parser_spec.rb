require "spec_helper"
require "./app/workers/dependency_file_parser"

RSpec.describe Workers::DependencyFileParser do
  subject(:worker) { described_class.new }
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
    subject(:perform) { worker.perform(body) }

    it "enqueues UpdateCheckers with the correct arguments" do
      expect(Workers::UpdateChecker).
        to receive(:perform_async).
        with(
          "repo" => body["repo"],
          "dependency_files" => body["dependency_files"],
          "dependency" => {
            "name" => "business",
            "version" => "1.4.0"
          })

      expect(Workers::UpdateChecker).
        to receive(:perform_async).
        with(
          "repo" => body["repo"],
          "dependency_files" => body["dependency_files"],
          "dependency" => {
            "name" => "statesman",
            "version" => "1.2.0"
          })

      perform
    end

    context "if an error is raised" do
      before do
        allow_any_instance_of(DependencyFileParsers::Ruby).
          to receive(:parse).
          and_raise("hell")
      end

      it "still raises, but also sends the error to sentry" do
        expect(Raven).to receive(:capture_exception).and_call_original
        expect { perform }.to raise_error("hell")
      end
    end
  end
end
