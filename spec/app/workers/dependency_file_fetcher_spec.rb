require "spec_helper"
require "./app/workers/dependency_file_fetcher"

RSpec.describe Workers::DependencyFileFetcher do
  subject(:worker) { described_class.new }
  let(:body) do
    {
      "repo" => {
        "name" => "gocardless/bump",
        "language" => "ruby"
      }
    }
  end

  describe "#perform" do
    subject(:perform) { worker.perform(body) }

    before do
      allow_any_instance_of(DependencyFileFetchers::Ruby).
        to receive(:files).
        and_return(
          [
            DependencyFile.new(name: "Gemfile", content: "xyz"),
            DependencyFile.new(name: "Gemfile.lock", content: "abc")
          ]
        )

      allow_any_instance_of(DependencyFileFetchers::Ruby).
        to receive(:commit).and_return("commitsha")
    end

    it "enqueues an DependencyFileParser with the correct arguments" do
      expect(Workers::DependencyFileParser).
        to receive(:perform_async).
        with(
          "repo" => body["repo"].merge("commit" => "commitsha"),
          "dependency_files" => [
            {
              "name" => "Gemfile",
              "content" => "xyz"
            },
            {
              "name" => "Gemfile.lock",
              "content" => "abc"
            }
          ]
        )
      perform
    end

    context "if an error is raised" do
      before do
        allow_any_instance_of(DependencyFileFetchers::Ruby).
          to receive(:files).and_raise("hell")
      end

      it "still raises, but also sends the error to sentry" do
        expect(Raven).to receive(:capture_exception).and_call_original
        expect { perform }.to raise_error("hell")
      end
    end
  end
end
