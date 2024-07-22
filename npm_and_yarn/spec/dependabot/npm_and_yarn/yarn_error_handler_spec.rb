# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_updater/yarn_lockfile_updater"
require "dependabot/npm_and_yarn/dependency_files_filterer"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/shared_helpers"
require "dependabot/errors"

RSpec.describe Dependabot::NpmAndYarn::YarnErrorHandler do
  subject(:error_handler) { described_class.new(dependencies: dependencies, dependency_files: dependency_files) }

  let(:dependencies) { [dependency] }
  let(:error) { instance_double(Dependabot::SharedHelpers::HelperSubprocessFailed, message: error_message) }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: [],
      previous_requirements: [],
      package_manager: "npm_and_yarn"
    )
  end
  let(:dependency_files) { project_dependency_files("yarn/git_dependency_local_file") }

  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com"
    })]
  end

  let(:dependency_name) { "@segment/analytics.js-integration-facebook-pixel" }
  let(:version) { "github:segmentio/analytics.js-integrations#2.4.1" }
  let(:yarn_lock) do
    dependency_files.find { |f| f.name == "yarn.lock" }
  end

  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }

  describe "#initialize" do
    it "initializes with dependencies and dependency files" do
      expect(error_handler.send(:dependencies)).to eq(dependencies)
      expect(error_handler.send(:dependency_files)).to eq(dependency_files)
    end
  end

  describe "#handle_error" do
    context "when the error message contains a yarn error code that is mapped" do
      let(:error_message) { "YN0002: Missing peer dependency" }

      it "raises the corresponding error class with the correct message" do
        expect { error_handler.handle_error(error, { yarn_lock: yarn_lock }) }
          .to raise_error(Dependabot::DependencyFileNotResolvable, /YN0002: Missing peer dependency/)
      end
    end

    context "when the error message contains a recognized pattern" do
      let(:error_message) { "Here is a recognized error pattern: authentication token not provided" }

      it "raises the corresponding error class with the correct message" do
        expect { error_handler.handle_error(error, { yarn_lock: yarn_lock }) }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure, /authentication token not provided/)
      end
    end

    context "when the error message contains unrecognized patterns" do
      let(:error_message) { "This is an unrecognized pattern that should not raise an error." }

      it "does not raise an error" do
        expect { error_handler.handle_error(error, { yarn_lock: yarn_lock }) }.not_to raise_error
      end
    end

    context "when the error message contains multiple unrecognized yarn error codes" do
      let(:error_message) do
        "➤ YN0000: ┌ Resolution step\n" \
          "➤ YN0000: ┌ Fetch step\n" \
          "➤ YN0099: │ some-dummy-package@npm:1.0.0 can't be found\n" \
          "➤ YN0099: │ some-dummy-package@npm:1.0.0: The remote server failed\n" \
          "➤ YN0000: └ Completed\n" \
          "➤ YN0000: Failed with errors in 1s 234ms"
      end

      it "does not raise an error" do
        expect { error_handler.handle_error(error, { yarn_lock: yarn_lock }) }.not_to raise_error
      end
    end

    context "when the error message contains multiple yarn error codes with the last one recognized" do
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

      it "raises a MisconfiguredTooling error with the correct message" do
        expect do
          error_handler.handle_yarn_error(error, { yarn_lock: yarn_lock })
        end.to raise_error(Dependabot::MisconfiguredTooling, /YN0080: .*The remote server failed/)
      end
    end

    context "when the error message contains a node version not satisfy regex and versions are extracted" do
      let(:error_message) do
        "➤ YN0000: ┌ Project validation\n" \
          "::group::Project validation\n" \
          "➤ YN0000: │ The current Node version v20.15.1 does not satisfy the required version 14.21.3.\n" \
          "::endgroup::\n" \
          "➤ YN0000: └ Completed\n" \
          "➤ YN0000: Failed with errors in 0s 6ms"
      end

      it "raises a ToolVersionNotSupported error with the correct versions" do
        expect do
          error_handler.handle_error(error, { yarn_lock: yarn_lock })
        end.to raise_error(Dependabot::ToolVersionNotSupported) do |e| # rubocop:disable Style/MultilineBlockChain
          expect(e.tool_name).to eq("Yarn")
          expect(e.detected_version).to eq("v20.15.1")
          expect(e.supported_versions).to eq("14.21.3")
        end
      end
    end

    context "when the error message contains SUB_DEP_LOCAL_PATH_TEXT" do
      let(:error_message) { "Some error occurred: refers to a non-existing file" }

      it "raises a DependencyFileNotResolvable error with the correct message" do
        expect { error_handler.handle_error(error, { yarn_lock: yarn_lock }) }
          .to raise_error(
            Dependabot::DependencyFileNotResolvable,
            %r{@segment\/analytics\.js-integration-facebook-pixel}
          )
      end
    end

    context "when the error message matches INVALID_PACKAGE_REGEX" do
      let(:error_message) { "Can't add \"invalid-package\": invalid" }

      it "raises a DependencyFileNotResolvable error with the correct message" do
        expect { error_handler.handle_error(error, { yarn_lock: yarn_lock }) }
          .to raise_error(
            Dependabot::DependencyFileNotResolvable,
            %r{@segment\/analytics\.js-integration-facebook-pixel}
          )
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

      it "raises the corresponding error class with the correct message" do
        expect do
          error_handler.handle_yarn_error(error, { yarn_lock: yarn_lock })
        end.to raise_error(Dependabot::DependencyFileNotResolvable, /YN0002: Missing peer dependency/)
      end
    end

    context "when the error message contains multiple yarn error codes" do
      let(:error_message) do
        "YN0001: Exception error\n" \
          "YN0002: Missing peer dependency\n" \
          "YN0016: Remote not found\n"
      end

      it "raises the last corresponding error class found with the correct message" do
        expect do
          error_handler.handle_yarn_error(error, { yarn_lock: yarn_lock })
        end.to raise_error(Dependabot::GitDependenciesNotReachable, /YN0016: Remote not found/)
      end
    end

    context "when the error message does not contain Yarn error codes" do
      let(:error_message) { "This message does not contain any known Yarn error codes." }

      it "does not raise any errors" do
        expect { error_handler.handle_yarn_error(error, { yarn_lock: yarn_lock }) }.not_to raise_error
      end
    end
  end

  describe "#handle_group_patterns" do
    let(:error_message) { "Here is a recognized error pattern: authentication token not provided" }
    let(:usage_error_message) { "Usage Error: This is a specific usage error.\nERROR" }

    context "when the error message contains a recognized pattern in the usage error message" do
      let(:error_message_with_usage_error) { "#{error_message}\n#{usage_error_message}" }

      it "raises the corresponding error class with the correct message" do
        expect { error_handler.handle_group_patterns(error, usage_error_message, { yarn_lock: yarn_lock }) }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure, /authentication token not provided/)
      end
    end

    context "when the error message contains a recognized pattern in the error message" do
      it "raises the corresponding error class with the correct message" do
        expect { error_handler.handle_group_patterns(error, "", { yarn_lock: yarn_lock }) }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure, /authentication token not provided/)
      end
    end

    context "when the error message does not contain recognized patterns" do
      let(:error_message) { "This is an unrecognized pattern that should not raise an error." }

      it "does not raise any errors" do
        expect { error_handler.handle_group_patterns(error, "", { yarn_lock: yarn_lock }) }.not_to raise_error
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
