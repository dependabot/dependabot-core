# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_updater/yarn_lockfile_updater"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/shared_helpers"
require "dependabot/errors"

RSpec.describe Dependabot::NpmAndYarn::YarnErrorHandler do
  subject(:error_handler) { described_class.new(dependencies: dependencies, dependency_files: dependency_files) }

  let(:dependencies) { [instance_double(Dependabot::Dependency, name: "test-dependency")] }
  let(:dependency_files) { [instance_double(Dependabot::DependencyFile, path: "path/to/yarn.lock")] }
  let(:error) { instance_double(Dependabot::SharedHelpers::HelperSubprocessFailed, message: error_message) }

  describe "#initialize" do
    it "initializes with dependencies and dependency files" do
      expect(error_handler.send(:dependencies)).to eq(dependencies)
      expect(error_handler.send(:dependency_files)).to eq(dependency_files)
    end
  end

  describe "#handle_error" do
    context "when the error message contains a yarn error code that is mapped" do
      let(:error_message) { "YN0002: Missing peer dependency" }

      it "raises the corresponding error class" do
        expect { error_handler.handle_error(error) }.to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "when the error message contains a recognized pattern" do
      let(:error_message) { "Here is a recognized error pattern: authentication token not provided" }

      it "raises the corresponding error class" do
        expect { error_handler.handle_error(error) }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "when the error message contains unrecognized patterns" do
      let(:error_message) { "This is an unrecognized pattern that should not raise an error." }

      it "does not raise an error" do
        expect { error_handler.handle_error(error) }.not_to raise_error
      end
    end

    context "when the error message contains unrecognized yarn error codes and patterns" do
      let(:error_message) do
        "➤ YN0000: ┌ Resolution step\n" \
          "➤ YN0000: ┌ Fetch step\n" \
          "➤ YN0099: │ some-dummy-package@npm:1.0.0 can't be found\n" \
          "➤ YN0099: │ some-dummy-package@npm:1.0.0: The remote server failed\n" \
          "➤ YN0000: └ Completed\n" \
          "➤ YN0000: Failed with errors in 1s 234ms"
      end

      it "does not raise an error" do
        expect { error_handler.handle_error(error) }.not_to raise_error
      end
    end

    context "when the error message contains a recognized yarn error code among multiple yarn error codes" do
      let(:error_message) do
        "➤ YN0000: ┌ Resolution step\n" \
          "➤ YN0002: │ dummy-package@npm:1.2.3 doesn't provide dummy (p1a2b3)\n" \
          "➤ YN0060: │ dummy-package@workspace:. provides dummy-tool (p4b5c6)\n" \
          "➤ YN0002: │ another-dummy-package@npm:4.5.6 doesn't provide dummy (p7d8e9)\n" \
          "➤ YN0000: └ Completed in 0s 123ms\n" \
          "➤ YN0000: ┌ Fetch step\n" \
          "➤ YN0080: │ some-dummy-package@npm:1.0.0 can't be found\n" \
          "➤ YN0080: │ some-dummy-package@npm:1.0.0: The remote server failed\n" \
          "➤ YN0000: └ Completed\n" \
          "➤ YN0000: Failed with errors in 1s 234ms"
      end

      it "raises a MisconfiguredTooling error" do
        expect do
          error_handler.handle_yarn_error(error_message)
        end.to raise_error(Dependabot::MisconfiguredTooling)
      end
    end

    context "when the error contains multiple unrecognized yarn error codes" do
      let(:error_message) do
        "➤ YN0000: ┌ Resolution step\n" \
          "➤ YN0000: ┌ Fetch step\n" \
          "➤ YN0013: │ some-dummy-package@npm:1.0.0 can't be found\n" \
          "➤ YN0035: │ some-dummy-package@npm:1.0.0: The remote server failed\n" \
          "➤ YN0035: │   Response Code: 404 (Not Found)\n" \
          "➤ YN0035: │   Request Method: GET\n" \
          "➤ YN0035: │   Request URL: https://dummy.artifactory...\n" \
          "➤ YN0000: └ Completed\n" \
          "➤ YN0000: Failed with errors in 1s 234ms"
      end

      it "does not raise an error" do
        expect { error_handler.handle_error(error) }.not_to raise_error
      end
    end
  end

  describe "#find_usage_error" do
    context "when there is a usage error in the message" do
      let(:error_message) { "Some initial text. Usage Error: This is a specific usage error.\nERROR" }

      it "returns the usage error text" do
        usage_error = error_handler.find_usage_error(error_message)
        expect(usage_error).to include("Usage Error: This is a specific usage error.\nERROR")
      end
    end

    context "when there is no usage error in the message" do
      let(:error_message) { "This message does not contain a usage error." }

      it "returns nil" do
        usage_error = error_handler.find_usage_error(error_message)
        expect(usage_error).to be_nil
      end
    end
  end

  describe "#handle_yarn_error" do
    context "when the error message contains yarn error codes" do
      let(:error_message) { "YN0002: Missing peer dependency" }

      it "raises the corresponding error class" do
        expect do
          error_handler.handle_yarn_error(error_message)
        end.to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "when the error message does not contain Yarn error codes" do
      let(:error_message) { "This message does not contain any known Yarn error codes." }

      it "does not raise any errors" do
        expect { error_handler.handle_yarn_error(error_message) }.not_to raise_error
      end
    end
  end

  describe "#pattern_in_message" do
    let(:patterns) { ["pattern1", /pattern2/] }

    context "when the message contains one of the patterns" do
      let(:message) { "This message contains pattern1 and pattern2." }

      it "returns true" do
        expect(error_handler.pattern_in_message(patterns, message)).to be(true)
      end
    end

    context "when the message does not contain any of the patterns" do
      let(:message) { "This message does not contain the patterns." }

      it "returns false" do
        expect(error_handler.pattern_in_message(patterns, message)).to be(false)
      end
    end
  end
end
