require "spec_helper"
require "bumper/workers/dependency_file_updater"

RSpec.describe Workers::DependencyFileUpdater do
  let(:worker) { described_class.new }
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

  describe "#process" do
    subject(:process) { worker.process(body) }
    before do
      allow_any_instance_of(DependencyFileUpdaters::RubyDependencyFileUpdater).
        to receive(:updated_dependency_files).
        and_return([DependencyFile.new(name: "Gemfile", content: "xyz")])
    end

    it "enqueues a PullRequestCreator with the correct arguments" do
      expect(Hutch).
        to receive(:publish).
        with(
          "bump.updated_files_to_create_pr_for",
          "repo" => body["repo"],
          "updated_dependency" => body["updated_dependency"],
          "updated_dependency_files" => [{
            "name" => "Gemfile",
            "content" => "xyz"
          }])
      process
    end

    context "if an error is raised" do
      before do
        allow(DependencyFileUpdaters::RubyDependencyFileUpdater).
          to receive(:new).
          and_raise("hell")
      end

      it "still raises, but also sends the error to sentry" do
        expect(Raven).to receive(:capture_exception).and_call_original
        expect { process }.to raise_error("hell")
      end
    end
  end
end
