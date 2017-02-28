require "spec_helper"
require "./app/workers/dependency_file_fetcher"
require "./app/workers/dependency_updater"

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
            DependencyFile.new(name: "Gemfile", content: fixture("Gemfile")),
            DependencyFile.new(
              name: "Gemfile.lock",
              content: fixture("Gemfile.lock")
            )
          ]
        )

      allow_any_instance_of(DependencyFileFetchers::Ruby).
        to receive(:commit).and_return("commitsha")
    end

    it "enqueues DependencyUpdaters with the correct arguments" do
      expect(Workers::DependencyUpdater).
        to receive(:perform_async).
        with(
          "repo" => body["repo"].merge("commit" => "commitsha"),
          "dependency_files" => [
            { "name" => "Gemfile", "content" => fixture("Gemfile") },
            { "name" => "Gemfile.lock", "content" => fixture("Gemfile.lock") }
          ],
          "dependency" => {
            "name" => "business",
            "version" => "1.4.0",
            "language" => "ruby",
            "previous_version" => nil
          }
        )

      expect(Workers::DependencyUpdater).
        to receive(:perform_async).
        with(
          "repo" => body["repo"].merge("commit" => "commitsha"),
          "dependency_files" => [
            { "name" => "Gemfile", "content" => fixture("Gemfile") },
            { "name" => "Gemfile.lock", "content" => fixture("Gemfile.lock") }
          ],
          "dependency" => {
            "name" => "statesman",
            "version" => "1.2.0",
            "language" => "ruby",
            "previous_version" => nil
          }
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
