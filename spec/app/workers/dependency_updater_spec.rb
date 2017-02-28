require "spec_helper"
require "./app/workers/dependency_updater"

RSpec.describe Workers::DependencyUpdater do
  let(:worker) { described_class.new }
  let(:body) do
    {
      "repo" => {
        "name" => "gocardless/bump",
        "language" => "ruby",
        "commit" => "commitsha"
      },
      "dependency" => {
        "name" => "business",
        "version" => "1.4.0",
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
    let(:stubbed_creator) { double("PullRequestCreator", create: nil) }

    context "when an update is required" do
      before do
        allow_any_instance_of(UpdateCheckers::Ruby).
          to receive(:needs_update?).and_return(true)
        allow_any_instance_of(UpdateCheckers::Ruby).
          to receive(:latest_version).and_return("1.5.0")

        allow_any_instance_of(DependencyFileUpdaters::Ruby).
          to receive(:updated_dependency_files).
          and_return([DependencyFile.new(name: "Gemfile", content: "xyz")])
      end

      it "enqueues a PullRequestCreator with the correct arguments" do
        expect(PullRequestCreator).to receive(:new) do |args|
          expect(args[:repo]).to eq("gocardless/bump")
          expect(args[:base_commit]).to eq("commitsha")
          expect(args[:dependency].to_h).to eq(
            "name" => "business",
            "version" => "1.5.0",
            "previous_version" => "1.4.0",
            "language" => "ruby"
          )
          expect(args[:files].map(&:to_h)).to eq(
            [{ "name" => "Gemfile", "content" => "xyz" }]
          )
        end.and_return(double(create: nil))
        perform
      end
    end

    context "when no update is required" do
      before do
        allow_any_instance_of(UpdateCheckers::Ruby).
          to receive(:needs_update?).and_return(false)
      end

      it "doesn't create a PR" do
        expect(PullRequestCreator).to_not receive(:new)
        perform
      end
    end

    context "if an error is raised" do
      before do
        allow_any_instance_of(UpdateCheckers::Ruby).
          to receive(:latest_version).and_return("1.7.0")
      end

      context "for a version conflict" do
        before do
          allow_any_instance_of(DependencyFileUpdaters::Ruby).
            to receive(:updated_dependency_files).
            and_raise(DependencyFileUpdaters::VersionConflict)
        end

        it "quietly finishes" do
          expect(Raven).to_not receive(:capture_exception)
          expect { perform }.to_not raise_error
        end
      end

      context "for a runtime error" do
        before do
          allow(DependencyFileUpdaters::Ruby).
            to receive(:new).
            and_raise("hell")
        end

        it "sends the error to sentry and raises" do
          expect(Raven).to receive(:capture_exception).and_call_original
          expect { perform }.to raise_error(/hell/)
        end
      end
    end
  end
end
