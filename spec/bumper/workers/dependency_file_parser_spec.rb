require "spec_helper"
require "bumper/workers/dependency_file_parser"

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

  describe "#process" do
    subject(:process) { worker.process(body) }

    it "enqueues UpdateCheckers with the correct arguments" do
      expect(Hutch).
        to receive(:publish).
        with(
          "bump.dependencies_to_check",
          "repo" => body["repo"],
          "dependency_files" => body["dependency_files"],
          "dependency" => {
            "name" => "business",
            "version" => "1.4.0"
          })

      expect(Hutch).
        to receive(:publish).
        with(
          "bump.dependencies_to_check",
          "repo" => body["repo"],
          "dependency_files" => body["dependency_files"],
          "dependency" => {
            "name" => "statesman",
            "version" => "1.2.0"
          })

      process
    end

    context "if an error is raised" do
      before do
        allow_any_instance_of(DependencyFileParsers::RubyDependencyFileParser).
          to receive(:parse).
          and_raise("hell")
      end

      it "still raises, but also sends the error to sentry" do
        expect(Raven).to receive(:capture_exception).and_call_original
        expect { process }.to raise_error("hell")
      end
    end
  end
end
