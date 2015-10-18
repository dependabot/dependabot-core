require "spec_helper"
require "./app/workers/dependency_file_fetcher"

RSpec.describe Workers::DependencyFileFetcher do
  subject(:worker) { described_class.new }
  before(:each) { allow(Hutch).to receive(:connect) }
  let(:body) do
    {
      "repo" => {
        "name" => "gocardless/bump",
        "language" => "ruby"
      }
    }
  end

  describe "#process" do
    subject(:process) { worker.process(body) }

    before do
      allow_any_instance_of(DependencyFileFetchers::RubyDependencyFileFetcher).
        to receive(:files).
        and_return([
          DependencyFile.new(name: "Gemfile", content: "xyz"),
          DependencyFile.new(name: "Gemfile.lock", content: "abc")
        ])
    end

    it "enqueues an DependencyFileParser with the correct arguments" do
      expect(Hutch).
        to receive(:publish).
        with(
          "bump.dependency_files_to_parse",
          "repo" => body["repo"],
          "dependency_files" => [
            {
              "name" => "Gemfile",
              "content" => "xyz"
            },
            {
              "name" => "Gemfile.lock",
              "content" => "abc"
            }
          ])
      process
    end

    context "if an error is raised" do
      before do
        allow_any_instance_of(
          DependencyFileFetchers::RubyDependencyFileFetcher
        ).to receive(:files).and_raise("hell")
      end

      it "still raises, but also sends the error to sentry" do
        expect(Raven).to receive(:capture_exception).and_call_original
        expect { process }.to raise_error("hell")
      end
    end
  end
end
