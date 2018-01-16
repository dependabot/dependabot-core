# frozen_string_literal: true

require "spec_helper"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::SharedHelpers do
  describe ".in_a_temporary_directory" do
    subject(:in_a_temporary_directory) do
      Dependabot::SharedHelpers.in_a_temporary_directory { output_dir.call }
    end

    let(:output_dir) { -> { Dir.pwd } }
    it "runs inside the temporary directory created" do
      expect(in_a_temporary_directory).to match(%r{tmp\/dependabot_+.})
    end

    it "yields the path to the temporary directory created" do
      expect { |b| described_class.in_a_temporary_directory(&b) }.
        to yield_with_args(Pathname)
    end
  end

  describe ".in_a_forked_process" do
    subject(:run_sub_process) do
      Dependabot::SharedHelpers.in_a_forked_process { task.call }
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
        expect { run_sub_process }.to_not(change { @bundle_setting })
      end
    end

    context "when the forked process raises an error" do
      let(:task) { -> { raise Exception, "hell" } }

      it "raises a ChildProcessFailed error" do
        expect { run_sub_process }.
          to raise_error(Dependabot::SharedHelpers::ChildProcessFailed)
      end
    end
  end

  describe ".run_helper_subprocess" do
    let(:function) { "example" }
    let(:args) { ["foo"] }
    let(:env) { nil }

    subject(:run_subprocess) do
      project_root = File.join(File.dirname(__FILE__), "../..")
      bin_path = File.join(project_root, "helpers/test/run.rb")
      command = "ruby #{bin_path}"
      Dependabot::SharedHelpers.run_helper_subprocess(
        command: command,
        function: function,
        args: args,
        env: env
      )
    end

    context "when the subprocess is successful" do
      it "returns the result" do
        expect(run_subprocess).to eq("function" => function, "args" => args)
      end

      context "with an env" do
        let(:env) { { "MIX_EXS" => "something" } }

        it "runs the function passed, as expected" do
          expect(run_subprocess).to eq("function" => function, "args" => args)
        end
      end
    end

    context "when the subprocess fails gracefully" do
      let(:function) { "error" }

      it "raises a HelperSubprocessFailed error" do
        expect { run_subprocess }.
          to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed)
      end
    end

    context "when the subprocess fails ungracefully" do
      let(:function) { "hard_error" }

      it "raises a HelperSubprocessFailed error" do
        expect { run_subprocess }.
          to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed)
      end
    end
  end
end
