# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/poetry_relocker"

RSpec.describe Dependabot::Python::PoetryRelocker do
  describe ".relock_if_enabled" do
    subject(:relock) do
      described_class.relock_if_enabled(package_names: ["six"], dependency_files: [pyproject], credentials: [])
    end

    let(:pyproject) { Dependabot::DependencyFile.new(name: "pyproject.toml", content: pyproject_content) }
    let(:pyproject_content) { "[tool.poetry.dependencies]\nsix = \"*\"\n" }

    def helper_failure(error_class)
      Dependabot::SharedHelpers::HelperSubprocessFailed.new(
        message: "Because relock-example depends on six (>=99) which doesn't match any versions, " \
                 "version solving failed.",
        error_class: error_class,
        error_context: {}
      )
    end

    context "when the experiment is off" do
      it "doesn't call the helper" do
        expect(Dependabot::SharedHelpers).not_to receive(:run_helper_subprocess)
        expect(relock).to be_nil
      end
    end

    context "when the experiment is on" do
      before { Dependabot::Experiments.register(:enable_native_poetry_helper, true) }

      context "when the project needs Poetry plugins" do
        let(:pyproject_content) { "[tool.poetry.requires-plugins]\npoetry-plugin-export = \">=1.8\"\n" }

        it "leaves it to `poetry update`" do
          expect(Dependabot::SharedHelpers).not_to receive(:run_helper_subprocess)
          expect(relock).to be_nil
        end
      end

      it "returns the lockfile and every locked version of the package" do
        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
          .with(hash_including(function: "relock_poetry_project", args: [Dir.pwd, ["six"]]))
          .and_return({ "lockfile" => "lock", "versions" => { "six" => ["1.16.0", "1.17.0"] } })

        expect(relock).to have_attributes(lockfile: "lock", versions: { "six" => %w(1.16.0 1.17.0) })
      end

      it "raises resolution failures so they aren't retried" do
        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
          .and_raise(helper_failure("SolverProblemError"))

        expect { relock }.to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, /version solving failed/)
      end

      it "returns nil for other helper failures so the caller uses `poetry update`" do
        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
          .and_raise(helper_failure("RuntimeError"))

        expect(relock).to be_nil
      end

      it "rejects malformed helper output" do
        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
          .and_return({ "lockfile" => "lock", "versions" => { "six" => "1.17.0" } })

        expect { relock }.to raise_error(TypeError)
      end
    end
  end
end
