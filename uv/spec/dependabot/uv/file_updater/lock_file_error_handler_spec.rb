# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/uv/file_updater/lock_file_error_handler"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::Uv::FileUpdater::LockFileErrorHandler do
  let(:error_handler) { described_class.new }

  describe "#handle_uv_error" do
    subject(:handle_uv_error) { error_handler.handle_uv_error(error) }

    context "when error contains 'No solution found when resolving dependencies'" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: detailed_uv_error,
          error_context: {}
        )
      end

      let(:detailed_uv_error) do
        <<~ERROR
          × No solution found when resolving dependencies:
          ╰─▶ Because package-a>=1.0.0 depends on package-b>=2.0.0
              and package-c<1.0.0 depends on package-b<2.0.0,
              we can conclude that package-a>=1.0.0 and package-c<1.0.0 are incompatible.
              And because your project depends on both package-a>=1.0.0 and package-c<1.0.0,
              we can conclude that your project's requirements are unsatisfiable.
        ERROR
      end

      it "raises DependencyFileNotResolvable with the detailed error message" do
        expect { handle_uv_error }.to raise_error(Dependabot::DependencyFileNotResolvable) do |raised_error|
          expect(raised_error.message).to include("No solution found when resolving dependencies")
          expect(raised_error.message).to include("package-a>=1.0.0 depends on package-b>=2.0.0")
          expect(raised_error.message).to include("your project's requirements are unsatisfiable")
        end
      end
    end

    context "when error contains 'ResolutionImpossible'" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "ResolutionImpossible: Could not find a version that satisfies the requirement requests==99.99.99",
          error_context: {}
        )
      end

      it "raises DependencyFileNotResolvable with the full error message" do
        expect { handle_uv_error }.to raise_error(
          Dependabot::DependencyFileNotResolvable,
          /ResolutionImpossible.*requests==99\.99\.99/
        )
      end
    end

    context "when error contains 'Failed to build'" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: failed_build_error,
          error_context: {}
        )
      end

      let(:failed_build_error) do
        <<~ERROR
          × Failed to build `some-package @
          │ file://dependabot_tmp_dir`
          ├─▶ The build backend returned an error
          ╰─▶ setuptools-scm was unable to detect version for dependabot_tmp_dir.
              Make sure you're either building from a fully intact git repository.
        ERROR
      end

      it "raises DependencyFileNotResolvable with the detailed error message" do
        expect { handle_uv_error }.to raise_error(Dependabot::DependencyFileNotResolvable) do |raised_error|
          expect(raised_error.message).to include("Failed to build")
          expect(raised_error.message).to include("setuptools-scm was unable to detect version")
          expect(raised_error.message).to include("Make sure you're either building from a fully intact git repository")
        end
      end
    end

    context "when error contains git reference not found" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Did not find branch or tag 'nonexistent-tag'",
          error_context: {}
        )
      end

      it "raises GitDependencyReferenceNotFound" do
        expect { handle_uv_error }.to raise_error(
          Dependabot::GitDependencyReferenceNotFound,
          /unknown package at nonexistent-tag/
        )
      end
    end

    context "when error contains git clone failure" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "git clone --filter=blob:none https://github.com/user/private-repo.git failed",
          error_context: {}
        )
      end

      it "raises GitDependenciesNotReachable" do
        expect { handle_uv_error }.to raise_error(
          Dependabot::GitDependenciesNotReachable,
          /github\.com/
        )
      end
    end

    context "when error contains git fetch credential failure" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: git_fetch_credential_error,
          error_context: {}
        )
      end

      let(:git_fetch_credential_error) do
        <<~ERROR
          Using CPython 3.11.14 interpreter at: /usr/local/.pyenv/versions/3.11.14/bin/python3.11
             Updating https://github.com/org/private-repo (7a71bd9f5ae50ea4c8b4629a97ab35b95bba3c8f)
            × Failed to download and build `private-repo @
            │ git+https://github.com/org/private-repo@7a71bd9f5ae50ea4c8b4629a97ab35b95bba3c8f#subdirectory=pkg`
            ├─▶ Git operation failed
            ├─▶ failed to clone into:
            │   /home/dependabot/.cache/uv/git-v0/db/12ae7fa1cd90829b
            ├─▶ failed to fetch commit `7a71bd9f5ae50ea4c8b4629a97ab35b95bba3c8f`
            ╰─▶ process didn't exit successfully: `/home/dependabot/bin/git fetch --force
                --update-head-ok 'https://github.com/org/private-repo'
                '+7a71bd9f5ae50ea4c8b4629a97ab35b95bba3c8f:refs/commit/7a71bd9f5ae50ea4c8b4629a97ab35b95bba3c8f'`
                (exit status: 128)
                --- stderr
                fatal: could not read Username for 'https://github.com': terminal prompts disabled
        ERROR
      end

      it "raises GitDependenciesNotReachable with the repository URL" do
        expect { handle_uv_error }.to raise_error(Dependabot::GitDependenciesNotReachable) do |raised_error|
          expect(raised_error.dependency_urls).to include("https://github.com/org/private-repo")
        end
      end
    end

    context "when error contains git credential failure without git+ URL" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "fatal: could not read Username for 'https://github.com': terminal prompts disabled",
          error_context: {}
        )
      end

      it "raises GitDependenciesNotReachable with the host URL" do
        expect { handle_uv_error }.to raise_error(Dependabot::GitDependenciesNotReachable) do |raised_error|
          expect(raised_error.dependency_urls).to include("https://github.com")
        end
      end
    end

    context "when error contains 401 authentication failure" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "HTTP status code: 401 for https://private-pypi.example.com/simple/package/",
          error_context: {}
        )
      end

      it "raises PrivateSourceAuthenticationFailure" do
        expect { handle_uv_error }.to raise_error(
          Dependabot::PrivateSourceAuthenticationFailure,
          /private-pypi\.example\.com/
        )
      end
    end

    context "when error contains 403 forbidden" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "403 forbidden when accessing https://pypi.private.org/packages/",
          error_context: {}
        )
      end

      it "raises PrivateSourceAuthenticationFailure" do
        expect { handle_uv_error }.to raise_error(
          Dependabot::PrivateSourceAuthenticationFailure,
          /pypi\.private\.org/
        )
      end
    end

    context "when error contains timeout" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Connection timed out while connecting to https://slow-registry.example.com",
          error_context: {}
        )
      end

      it "raises PrivateSourceTimedOut" do
        expect { handle_uv_error }.to raise_error(
          Dependabot::PrivateSourceTimedOut,
          /slow-registry\.example\.com/
        )
      end
    end

    context "when error contains SSL certificate failure" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "SSLError: certificate verify failed for https://self-signed.example.com",
          error_context: {}
        )
      end

      it "raises PrivateSourceCertificateFailure" do
        expect { handle_uv_error }.to raise_error(
          Dependabot::PrivateSourceCertificateFailure,
          /self-signed\.example\.com/
        )
      end
    end

    context "when error contains out of disk space" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Failed to write file: [Errno 28] No space left on device",
          error_context: {}
        )
      end

      it "raises OutOfDisk" do
        expect { handle_uv_error }.to raise_error(Dependabot::OutOfDisk)
      end
    end

    context "when error contains memory error" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Process failed with MemoryError",
          error_context: {}
        )
      end

      it "raises OutOfMemory" do
        expect { handle_uv_error }.to raise_error(Dependabot::OutOfMemory)
      end
    end

    context "when error contains Python version requirement" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Package requires Python version >=3.9 but running 3.8",
          error_context: {}
        )
      end

      it "raises DependencyFileNotResolvable with Python version message" do
        expect { handle_uv_error }.to raise_error(Dependabot::DependencyFileNotResolvable) do |raised_error|
          expect(raised_error.message).to include("Python version incompatibility")
        end
      end
    end

    context "when error contains package not found" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "No matching distribution found for nonexistent-package==1.0.0",
          error_context: {}
        )
      end

      it "raises DependencyFileNotResolvable" do
        expect { handle_uv_error }.to raise_error(Dependabot::DependencyFileNotResolvable) do |raised_error|
          expect(raised_error.message).to include("No matching distribution found")
        end
      end
    end

    context "when error contains a TOML parse error" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Failed to parse: `pyproject.toml`\nTOML parse error at line 5",
          error_context: {}
        )
      end

      it "raises DependencyFileNotParseable" do
        expect { handle_uv_error }.to raise_error(Dependabot::DependencyFileNotParseable, /pyproject\.toml/)
      end
    end

    context "when error contains a TOML parse error for a nested file" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Failed to parse: `subdir/pyproject.toml`\nExpected '=' after key",
          error_context: {}
        )
      end

      it "raises DependencyFileNotParseable with the file path" do
        expect { handle_uv_error }.to raise_error(Dependabot::DependencyFileNotParseable) do |raised_error|
          expect(raised_error.message).to include("subdir/pyproject.toml")
        end
      end
    end

    context "when error contains a pyproject schema error (missing project field)" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Field `project.name` is required in pyproject.toml",
          error_context: {}
        )
      end

      it "raises DependencyFileNotParseable for pyproject.toml" do
        expect { handle_uv_error }.to raise_error(Dependabot::DependencyFileNotParseable, /pyproject\.toml/)
      end
    end

    context "when error contains a workspace member error" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Failed to find workspace member `packages/missing-pkg`",
          error_context: {}
        )
      end

      it "raises DependencyFileNotResolvable" do
        expect { handle_uv_error }.to raise_error(Dependabot::DependencyFileNotResolvable) do |raised_error|
          expect(raised_error.message).to include("workspace member")
        end
      end
    end

    context "when error contains a path dependency error" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Failed to read `../local-lib/pyproject.toml`",
          error_context: {}
        )
      end

      it "raises PathDependenciesNotReachable" do
        expect { handle_uv_error }.to raise_error(Dependabot::PathDependenciesNotReachable) do |raised_error|
          expect(raised_error.dependencies).to include("../local-lib/pyproject.toml")
        end
      end
    end

    context "when error contains a UV misconfiguration (unknown field)" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "unknown field `foo`, expected one of `dependencies`, `dev-dependencies`",
          error_context: {}
        )
      end

      it "raises MisconfiguredTooling" do
        expect { handle_uv_error }.to raise_error(Dependabot::MisconfiguredTooling) do |raised_error|
          expect(raised_error.tool_name).to eq("uv")
          expect(raised_error.message).to include("unknown field")
        end
      end
    end

    context "when error contains an HTTP 500 server error" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "HTTP status code: 500 for https://registry.example.com/simple/package/",
          error_context: {}
        )
      end

      it "raises PrivateSourceBadResponse" do
        expect { handle_uv_error }.to raise_error(Dependabot::PrivateSourceBadResponse) do |raised_error|
          expect(raised_error.source).to include("registry.example.com")
        end
      end
    end

    context "when error contains an HTTP 502 bad gateway error" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "HTTP status code: 502 for https://pypi.org/simple/package/",
          error_context: {}
        )
      end

      it "raises PrivateSourceBadResponse" do
        expect { handle_uv_error }.to raise_error(Dependabot::PrivateSourceBadResponse) do |raised_error|
          expect(raised_error.source).to include("pypi.org")
        end
      end
    end

    context "when error contains a connection refused error" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "ConnectionError: connection refused while connecting to https://down.example.com",
          error_context: {}
        )
      end

      it "raises DependencyFileNotResolvable with network error context" do
        expect { handle_uv_error }.to raise_error(Dependabot::DependencyFileNotResolvable) do |raised_error|
          expect(raised_error.message).to include("Network error")
        end
      end
    end

    context "when error contains a required uv version mismatch" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Required uv version `>=0.5.0` does not match the running version `0.4.0`",
          error_context: {}
        )
      end

      it "raises ToolVersionNotSupported" do
        expect { handle_uv_error }.to raise_error(Dependabot::ToolVersionNotSupported) do |raised_error|
          expect(raised_error.message).to include(">=0.5.0")
          expect(raised_error.message).to include("0.4.0")
        end
      end
    end

    context "when error contains conflicting dependency versions" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: conflicting_deps_error,
          error_context: {}
        )
      end

      let(:conflicting_deps_error) do
        <<~ERROR
          × No solution found when resolving dependencies:
          ╰─▶ Because flask==2.0.0 depends on werkzeug>=2.0 and your project depends on werkzeug==1.0.0,
              we can conclude that flask==2.0.0 is incompatible with your project.
        ERROR
      end

      it "raises UpdateNotPossible with the conflicting dependencies" do
        expect { handle_uv_error }.to raise_error(Dependabot::UpdateNotPossible) do |raised_error|
          expect(raised_error.dependencies).to include("flask")
          expect(raised_error.dependencies).to include("werkzeug")
        end
      end
    end

    context "when error is unknown" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Some completely unknown error occurred",
          error_context: {}
        )
      end

      it "re-raises the original error" do
        expect { handle_uv_error }.to raise_error(
          Dependabot::SharedHelpers::HelperSubprocessFailed,
          /Some completely unknown error occurred/
        )
      end
    end
  end
end
