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

    context "when error contains a CLI argument conflict (e.g. --default-index used multiple times)" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "error: the argument '--default-index <DEFAULT_INDEX>' cannot be used multiple times\n\n" \
                   "Usage: uv lock [OPTIONS]\n\nFor more information, try '--help'.",
          error_context: {}
        )
      end

      it "raises MisconfiguredTooling" do
        expect { handle_uv_error }.to raise_error(Dependabot::MisconfiguredTooling) do |raised_error|
          expect(raised_error.tool_name).to eq("uv")
          expect(raised_error.message).to include("--default-index")
        end
      end
    end

    context "when unhandled uv error starts with 'Using CPython' (conflicting URLs)" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: conflicting_urls_error,
          error_context: {}
        )
      end

      let(:conflicting_urls_error) do
        <<~ERROR
          Using CPython 3.11.14 interpreter at: /usr/local/.pyenv/versions/3.11.14/bin/python3.11
             Updating https://github.com/org/repo-a (HEAD)
             Updating https://github.com/org/repo-b (HEAD)
              Updated https://github.com/org/repo-a (c153cf38a632381e617475adff6f71cc9fe8087d)
              Updated https://github.com/org/repo-b (0fd65b7f549ed22c154e2e64c20b88a73a1a9e56)
            × Failed to resolve dependencies for `my-cli` (v0.2.1)
            ╰─▶ Requirements contain conflicting URLs for package `my-services`
                in split `python_full_version >= '3.14' and sys_platform == 'win32'`:
                - git+https://github.com/org/repo-a@v0.x
                - git+https://github.com/org/repo-b
            help: `my-cli` (v0.2.1) was included because
                  `my-project:dev` (v2.0.0) depends on `my-cli`
        ERROR
      end

      it "raises DependencyFileNotResolvable with the error details" do
        expect { handle_uv_error }.to raise_error(Dependabot::DependencyFileNotResolvable) do |raised_error|
          expect(raised_error.message).to include("Failed to resolve dependencies")
          expect(raised_error.message).to include("conflicting URLs")
          expect(raised_error.message).not_to include("Using CPython")
        end
      end
    end

    context "when unhandled uv error starts with 'Using CPython' (uv.lock parse failure)" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: uv_lock_parse_error,
          error_context: {}
        )
      end

      let(:uv_lock_parse_error) do
        <<~ERROR
          Using CPython 3.11.14 interpreter at: /usr/local/.pyenv/versions/3.11.14/bin/python3.11
          error: Failed to parse `uv.lock`
            Caused by: Dependency `soupsieve` has missing `source` field but has more than one matching package
        ERROR
      end

      it "raises DependencyFileNotResolvable and strips the CPython prefix" do
        expect { handle_uv_error }.to raise_error(Dependabot::DependencyFileNotResolvable) do |raised_error|
          expect(raised_error.message).to include("Failed to parse `uv.lock`")
          expect(raised_error.message).not_to include("Using CPython")
        end
      end
    end

    context "when error contains 'Using CPython' mid-message (not at start)" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "some other error\nUsing CPython 3.11.14 interpreter at: /usr/bin/python3.11\ndetails",
          error_context: {}
        )
      end

      it "re-raises the original error" do
        expect { handle_uv_error }.to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed)
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

  describe "#conflict_package_names" do
    subject(:names) { error_handler.conflict_package_names(message) }

    context "when the bumped package needs a newer peer" do
      let(:message) do
        <<~ERROR
          × No solution found when resolving dependencies for split (markers:
          │ python_full_version >= '3.12'):
          ╰─▶ Because opentelemetry-sdk==1.25.0 depends on opentelemetry-api==1.25.0
              and your project depends on opentelemetry-api==1.26.0, we can conclude
              that your project and opentelemetry-sdk==1.25.0 are incompatible.
              And because your project depends on opentelemetry-sdk==1.25.0, we can
              conclude that your project's requirements are unsatisfiable.
        ERROR
      end

      it "returns every package named in the conflict, without markers" do
        expect(names).to eq(%w(opentelemetry-sdk opentelemetry-api))
      end
    end

    context "when a requirement has extras and mixed case" do
      let(:message) do
        "Because Foo_Bar[extra]>=2.0 depends on baz<1 and your project depends on baz==1.2, ..."
      end

      it "normalises the names" do
        expect(names).to eq(%w(foo-bar baz))
      end
    end

    context "when uv prints forked-resolution markers after the names" do
      let(:message) do
        <<~ERROR
          × No solution found when resolving dependencies for split (sys_platform != 'emscripten'):
          ╰─▶ Because httpx2{sys_platform != 'emscripten'}==2.13.0 depends on httpcore2{sys_platform != 'emscripten'}==2.13.0
              and your project depends on httpcore2{sys_platform != 'emscripten'}==2.10.0, we can conclude that
              httpx2{sys_platform != 'emscripten'}==2.13.0 and your project are incompatible.
        ERROR
      end

      it "reads the names around the markers" do
        expect(names).to eq(%w(httpx2 httpcore2))
      end
    end

    context "when a requirement has extras and a marker" do
      let(:message) { "Because foo[bar]{python_full_version >= '3.12'}>=1 depends on ..." }

      it "returns the name only" do
        expect(names).to eq(["foo"])
      end
    end

    context "when a name ends in a non-alphanumeric character" do
      let(:message) { "Because foo-==1 is odd" }

      it "returns no name" do
        expect(names).to eq([])
      end
    end

    context "when a name is a single character" do
      let(:message) { "Because a==1 is short" }

      it "returns the name" do
        expect(names).to eq(["a"])
      end
    end

    context "with real uv conflict messages" do
      # crates/uv/tests/lock/lock.rs:4319 (astral-sh/uv@5411378e)
      it "reads a direct conflict between two packages" do
        message = <<~ERROR
          error: No solution found when resolving dependencies
            cause: Because anyio==3.7.0 depends on idna==3.2 and your project depends on anyio==3.7.0, we can conclude that your project depends on idna==3.2.
                   And because your project depends on idna==3.6, we can conclude that your project's requirements are unsatisfiable.
        ERROR
        expect(error_handler.conflict_package_names(message)).to eq(%w(anyio idna))
      end

      # crates/uv/tests/lock/lock.rs:41086 (astral-sh/uv@5411378e)
      it "reads a peer forked by a marker" do
        message = <<~ERROR
          error: No solution found when resolving dependencies for split (markers: python_full_version >= '3.11')
            cause: Because pandas==1.5.3 depends on numpy{python_full_version >= '3.10'}>=1.21.0 and your project depends on numpy==1.20.3, we can conclude that your project and pandas==1.5.3 are incompatible.
                   And because your project depends on pandas==1.5.3, we can conclude that your project's requirements are unsatisfiable.
        ERROR
        expect(error_handler.conflict_package_names(message)).to eq(%w(pandas numpy))
      end

      # crates/uv/tests/lock/lock.rs:43886 (astral-sh/uv@5411378e)
      it "reads a forked package with and without a specifier" do
        message = <<~ERROR
          error: No solution found when resolving dependencies for split (markers: python_full_version < '3.14' and sys_platform == 'other')
            cause: Because your project depends on anyio{sys_platform == 'other'} and anyio{python_full_version < '3.14'}>=4.4.0, we can conclude that your project's requirements are unsatisfiable.
        ERROR
        expect(error_handler.conflict_package_names(message)).to eq(%w(anyio))
      end

      # generated with uv 0.11.25 (`uv lock`, opentelemetry-sdk/api pinned under `python_version` markers)
      it "reads a forked marker that uv wrapped across lines" do
        message = <<~ERROR
          × No solution found when resolving dependencies for split (markers:
          │ python_full_version >= '3.12'):
          ╰─▶ Because opentelemetry-sdk==1.25.0 depends on opentelemetry-api==1.25.0
              and your project depends on opentelemetry-api{python_full_version
              >= '3.12'}==1.26.0, we can conclude that your project and
              opentelemetry-sdk{python_full_version >= '3.12'}==1.25.0 are
              incompatible.
              And because your project depends on
              opentelemetry-sdk{python_full_version >= '3.12'}==1.25.0, we can
              conclude that your project's requirements are unsatisfiable.
        ERROR
        expect(error_handler.conflict_package_names(message)).to eq(%w(opentelemetry-sdk opentelemetry-api))
      end

      # crates/uv/tests/pip_compile/pip_compile.rs:11566 (astral-sh/uv@5411378e)
      it "reads a package with extras" do
        message = <<~ERROR
          error: No solution found when resolving dependencies
            cause: Because only recursive-demo[outer]==1.0.0 is available and recursive-demo[outer]==1.0.0 depends on recursive-demo{sys_platform == 'darwin'}>=2, we can conclude that all versions of recursive-demo[outer] cannot be used.
                   And because you require recursive-demo[outer], we can conclude that your requirements are unsatisfiable.
        ERROR
        expect(error_handler.conflict_package_names(message)).to eq(%w(recursive-demo))
      end

      # crates/uv/tests/lock/lock.rs:6896 (astral-sh/uv@5411378e)
      it "skips dependency groups and the project's own extras" do
        message = <<~ERROR
          error: No solution found when resolving dependencies
            cause: Because project:project1 depends on sortedcontainers==2.3.0 and project[project2] depends on sortedcontainers==2.4.0, we can conclude that project:project1 and project[project2] are incompatible.
                   And because your project requires project[project2] and project:project1, we can conclude that your project's requirements are unsatisfiable.
        ERROR
        expect(error_handler.conflict_package_names(message)).to eq(%w(sortedcontainers))
      end

      # crates/uv/tests/sync/sync.rs:2496 (astral-sh/uv@5411378e)
      it "reads a Python conflict reached through a dependency group" do
        message = <<~ERROR
          error: No solution found when resolving dependencies for split (markers: python_full_version == '3.8.*')
            cause: Because the requested Python version (>=3.8) does not satisfy Python>=3.9 and sphinx==7.2.6 depends on Python>=3.9, we can conclude that sphinx==7.2.6 cannot be used.
                   And because only sphinx<=7.2.6 is available, we can conclude that sphinx>=7.2.6 cannot be used.
                   And because pharaohs-tomp:mygroup depends on sphinx>=7.2.6 and your project requires pharaohs-tomp:mygroup, we can conclude that your project's requirements are unsatisfiable.
        ERROR
        # `python` is not a package; the top-level dependency filter drops it.
        expect(error_handler.conflict_package_names(message)).to eq(%w(python sphinx))
      end

      # crates/uv/tests/lock/lock.rs:8207 (astral-sh/uv@5411378e)
      it "reads a Python conflict with version ranges" do
        message = <<~ERROR
          error: No solution found when resolving dependencies for split (markers: python_full_version >= '3.7' and python_full_version < '3.7.9')
            cause: Because the requested Python version (>=3.7) does not satisfy Python>=3.7.9 and pygls>=1.1.0,<=1.2.1 depends on Python>=3.7.9,<4, we can conclude that pygls>=1.1.0,<=1.2.1 cannot be used.
                   And because only the following versions of pygls are available:
                       pygls<=1.2.1
                       pygls>=1.3.0
                   we can conclude that pygls>=1.1.0,<1.3.0 cannot be used. (1)

                   Because the requested Python version (>=3.7) does not satisfy Python>=3.8 and pygls==1.3.0 depends on Python>=3.8, we can conclude that pygls==1.3.0 cannot be used.
                   And because only pygls<=1.3.0 is available, we can conclude that pygls>=1.3.0 cannot be used.
                   And because we know from (1) that pygls>=1.1.0,<1.3.0 cannot be used, we can conclude that pygls>=1.1.0 cannot be used.
                   And because your project depends on pygls>=1.1.0, we can conclude that your project's requirements are unsatisfiable.
        ERROR
        # `python` is not a package; the top-level dependency filter drops it.
        expect(error_handler.conflict_package_names(message)).to eq(%w(python pygls))
      end

      # crates/uv/tests/lock/lock.rs:41891 (astral-sh/uv@5411378e)
      it "reads a wildcard specifier" do
        message = <<~ERROR
          error: No solution found when resolving dependencies
            cause: Because only anyio<=4.3.0 is available and your project depends on anyio==5.4.*, we can conclude that your project's requirements are unsatisfiable.
        ERROR
        expect(error_handler.conflict_package_names(message)).to eq(%w(anyio))
      end

      # crates/uv/tests/pip_compile/pip_compile.rs:19102 (astral-sh/uv@5411378e)
      it "reads local versions and skips uv's virtual system packages" do
        message = <<~ERROR
          error: No solution found when resolving dependencies
            cause: Because torchvision==0.17.1+cu118 depends on system:cuda==11.8 and torch>=2.2.1+cu121 depends on system:cuda==12.1, we can conclude that torch>=2.2.1+cu121 and torchvision==0.17.1+cu118 are incompatible.
                   And because you require torch==2.2.1+cu121 and torchvision==0.17.1+cu118, we can conclude that your requirements are unsatisfiable.
        ERROR
        expect(error_handler.conflict_package_names(message)).to eq(%w(torchvision torch))
      end
    end

    context "when the message is a long run of digits or brackets" do
      %w(0 0[).each do |unit|
        it "returns no names for #{unit.inspect} repeated" do
          expect(error_handler.conflict_package_names(unit * 100_000)).to eq([])
        end
      end
    end
  end
end
