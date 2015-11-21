require "spec_helper"
require "./lib/shared_helpers"

RSpec.describe SharedHelpers do
  describe ".in_a_forked_process" do
    subject(:run_sub_process) do
      SharedHelpers.in_a_forked_process { task.call }
    end

    context "when the forked process returns a value" do
      let(:task) { -> { "all good" } }

      it "returns the return value of the sub-process" do
        expect(run_sub_process).to eq("all good")
      end
    end

    context "when the forked process sets an environment variable" do
      let(:task) { -> { @bundle_setting = "new" } }

      it "doesn't persist the change" do
        expect { run_sub_process }.to_not change { @bundle_setting }
      end
    end

    context "when the forked process raises an error" do
      let(:task) { -> { raise "hell" } }

      it "raises a ChildProcessFailed error" do
        expect { run_sub_process }.
          to raise_error(SharedHelpers::ChildProcessFailed)
      end
    end
  end
end
