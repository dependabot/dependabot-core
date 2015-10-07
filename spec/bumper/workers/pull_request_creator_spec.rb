require "spec_helper"
require "./app/workers/pull_request_creator"

RSpec.describe Workers::PullRequestCreator do
  subject(:worker) { described_class.new }
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
      "updated_dependency_files" => [
        { "name" => "Gemfile", "content" => "xyz" },
        { "name" => "Gemfile.lock", "content" => "xyz" }
      ]
    }
  end

  describe "#process" do
    let(:stubbed_creator) { double("PullRequestCreator", create: nil) }

    it "passes the correct arguments to pull request creator" do
      expect(PullRequestCreator).
        to receive(:new).
        with(repo: "gocardless/bump",
             dependency: an_instance_of(Dependency),
             files: an_instance_of(Array)).
        and_return(stubbed_creator)

      expect(stubbed_creator).to receive(:create)

      worker.process(body)
    end

    context "if an error is raised" do
      before do
        allow_any_instance_of(::PullRequestCreator).
          to receive(:create).
          and_raise("hell")
      end

      it "still raises, but also sends the error to sentry" do
        expect(Raven).to receive(:capture_exception).and_call_original
        expect { worker.process(body) }.to raise_error("hell")
      end
    end
  end
end
