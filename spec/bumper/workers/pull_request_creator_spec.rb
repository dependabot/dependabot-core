require "spec_helper"
require "bumper/workers/pull_request_creator"

RSpec.describe Workers::PullRequestCreator do
  subject(:worker) { described_class.new }
  let(:sqs_message) { double("sqs_message") }
  let(:body) do
    {
      "repo" => {
        "name" => "gocardless/bump",
        "language" => "ruby",
      },
      "updated_dependency" => {
        "name" => "business",
        "version" => "1.5.0",
      },
      "updated_dependency_files" => [
        { "name" => "Gemfile", "content" => "xyz" },
        { "name" => "Gemfile.lock", "content" => "xyz" },
      ]
    }
  end

  it { }

  # describe "#perform" do
  #   it "passes updated files to the next phase" do
  #     allow_any_instance_of(DependencyFileUpdaters::RubyDependencyFileUpdater).
  #       to receive(:updated_dependency_files)
  #     expect(worker).to receive(:do_something_with)
  #     worker.perform(sqs_message, body)
  #   end
  # end
end
