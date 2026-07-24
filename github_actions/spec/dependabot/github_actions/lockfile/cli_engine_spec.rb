# typed: false
# frozen_string_literal: true

require "spec_helper"
require "json"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/command_helpers"
require "dependabot/github_actions/lockfile"

# These specs lock the exit-code contract validated live against the real
# gh-actions-lock binary: the CLI uses a non-zero exit purely to signal
# `valid:false` (findings exist) while still writing the full structured result
# to stdout. CliEngine#run must therefore parse stdout regardless of exit status,
# and the findings — not the exit code — drive control flow. We stub the
# subprocess layer so no binary or network is needed.
RSpec.describe Dependabot::GithubActions::Lockfile::CliEngine do
  subject(:engine) { described_class.new([]) }

  let(:workflow) do
    Dependabot::DependencyFile.new(
      name: ".github/workflows/ci.yml",
      content: "on: push\njobs: {}\n"
    )
  end

  let(:lockfile) do
    Dependabot::DependencyFile.new(name: ".github/workflows/actions.lock", content: "version: v0.0.2\n")
  end

  # Fake ProcessStatus exposing just the exitstatus CliEngine#invoke reads.
  def process_double(exitstatus)
    instance_double(Process::Status, exitstatus: exitstatus, success?: exitstatus.zero?)
  end

  def stub_subprocess(stdout:, exitstatus:, stderr: "Scanning 1 workflow\nResolving actions\n")
    allow(Dependabot::CommandHelpers)
      .to receive(:capture3_with_timeout)
      .and_return([stdout, stderr, process_double(exitstatus)])
  end

  # The run/invoke exit-code contract, exercised through the sole public entrypoint
  # (relock). The CLI writes structured JSON to stdout regardless of exit status, so
  # parse failures and tool failures must be told apart by exit code, not presence of
  # output. (Exit 2 + stderr is covered by the corrupt-lockfile block below.)
  describe "#relock when stdout is genuinely unparseable at a parse-expected exit (1)" do
    before { stub_subprocess(stdout: "not json at all", exitstatus: 1, stderr: "") }

    it "raises EngineError — exit 0/1 must carry JSON" do
      expect { engine.relock(workflow_files: [workflow], lockfile: lockfile) }
        .to raise_error(Dependabot::GithubActions::Lockfile::EngineError, /unparseable JSON/)
    end
  end

  describe "#relock when the binary fails to start (capture3 returns a nil status)" do
    # capture3_with_timeout swallows Errno::ENOENT (binary missing / not executable)
    # by returning a nil status with the OS error on stderr. Without the guard in
    # CliEngine#invoke this coerces to exit 0 and surfaces as a misleading
    # "unparseable JSON" error. It must instead be a clear "failed to start".
    before do
      allow(Dependabot::CommandHelpers)
        .to receive(:capture3_with_timeout)
        .and_return(["", "No such file or directory - gh-actions-lock", nil])
    end

    it "raises EngineError reporting the binary failed to start, not unparseable JSON" do
      expect { engine.relock(workflow_files: [workflow], lockfile: lockfile) }
        .to raise_error(
          Dependabot::GithubActions::Lockfile::EngineError,
          /failed to start.*No such file or directory/m
        )
    end
  end

  describe "#relock surfacing a structured blocking finding (exit 1)" do
    let(:body) do
      {
        "cli_version" => "v0.0.5", "lockfile_version" => "v0.0.2", "valid" => false,
        "findings" => [
          { "category" => "impostor-commit", "severity" => "error",
            "dependency" => "actions/checkout@v5", "detail" => "locked SHA not reachable from any branch" }
        ]
      }
    end

    before { stub_subprocess(stdout: JSON.generate(body), exitstatus: 1) }

    it "reaches the finding mapper (previously dead code) and raises the mapped error" do
      expect { engine.relock(workflow_files: [workflow], lockfile: lockfile) }
        .to raise_error(Dependabot::GithubActions::Lockfile::UnresolvableDependency, %r{actions/checkout@v5})
    end
  end

  describe "#relock with an unknown error finding (exit 1)" do
    let(:body) do
      {
        "findings" => [
          { "category" => "new-unhandled-error", "severity" => "error" }
        ]
      }
    end

    before { stub_subprocess(stdout: JSON.generate(body), exitstatus: 1) }

    it "fails closed" do
      expect { engine.relock(workflow_files: [workflow], lockfile: lockfile) }
        .to raise_error(Dependabot::GithubActions::Lockfile::EngineError, /new-unhandled-error/)
    end
  end

  describe "#relock with only an onboarding-required finding (exit 1)" do
    # The real binary's mixed default (no-onboard) response: three arrays populate
    # concurrently regardless of the --json selector.
    let(:body) do
      {
        "updated" => [],
        "workflows" => [{ "path" => ".github/workflows/a.yml" }],
        "findings" => [
          { "workflow" => ".github/workflows/b.yml", "category" => "onboarding-required",
            "severity" => "error", "confidence" => "high",
            "detail" => "workflow .github/workflows/b.yml is not tracked in the lockfile" }
        ]
      }
    end

    before { stub_subprocess(stdout: JSON.generate(body), exitstatus: 1) }

    it "does not raise — onboarding-required is a skip, not a blocker" do
      expect { engine.relock(workflow_files: [workflow], lockfile: lockfile) }
        .not_to raise_error
    end
  end

  describe "#relock when the engine reports a lock-PINNED action as un-onboarded (lock unreadable)" do
    # The lock pins actions/checkout@v4 under ci.yml, but the engine reports
    # onboarding-required for that very action — the symptom of a malformed
    # dependencies entry it silently swallowed to empty (it could not see a pin we
    # can). This is the contradiction we must fail loud on, distinct from a NEW
    # action the lock genuinely does not pin (the next describe block).
    let(:tracked_lockfile) do
      Dependabot::DependencyFile.new(
        name: ".github/workflows/actions.lock",
        content: <<~LOCK
          version: v0.0.2
          workflows:
            ".github/workflows/ci.yml":
              - "actions/checkout@v4"
        LOCK
      )
    end

    let(:body) do
      {
        "updated" => [], "workflows" => [],
        "findings" => [
          { "workflow" => ".github/workflows/ci.yml", "category" => "onboarding-required",
            "severity" => "error", "confidence" => "high", "dependency" => "actions/checkout@v4",
            "detail" => "actions/checkout@v4 has no lockfile entry; --no-onboard refuses to add new " \
                        "workflows or actions" }
        ]
      }
    end

    before { stub_subprocess(stdout: JSON.generate(body), exitstatus: 1) }

    it "raises DependencyFileNotParseable rather than silently skipping the relock" do
      expect { engine.relock(workflow_files: [workflow], lockfile: tracked_lockfile) }
        .to raise_error(Dependabot::DependencyFileNotParseable, /could not read.*malformed or unreadable/m)
    end
  end

  describe "#relock when a tracked workflow gains a NEW unpinned action (the dry-run case)" do
    # Reproduces the real bin/dry-run.rb failure: a workflow the lock DOES track
    # (ci.yml, pinning checkout@v4) references a second action with no pin
    # (actions/setup-node@v4). Under --no-onboard the engine refuses to add the new
    # action and emits onboarding-required AT ACTION GRANULARITY (`dependency` names
    # the unpinned action, `workflow` is the tracked file). This is a legitimate
    # skip-and-log, NOT a corrupt-lock error: the lock simply does not pin that action
    # yet. Before the action-level discriminator, this falsely raised
    # DependencyFileNotParseable and aborted the whole update.
    let(:tracked_lockfile) do
      Dependabot::DependencyFile.new(
        name: ".github/workflows/actions.lock",
        content: <<~LOCK
          version: v0.0.2
          workflows:
            ".github/workflows/ci.yml":
              - "actions/checkout@v4"
        LOCK
      )
    end

    let(:body) do
      {
        "updated" => [], "workflows" => [{ "path" => ".github/workflows/ci.yml" }],
        "findings" => [
          { "workflow" => ".github/workflows/ci.yml", "category" => "onboarding-required",
            "severity" => "error", "confidence" => "high", "dependency" => "actions/setup-node@v4",
            "detail" => "actions/setup-node@v4 has no lockfile entry; --no-onboard refuses to add new " \
                        "workflows or actions" }
        ]
      }
    end

    before { stub_subprocess(stdout: JSON.generate(body), exitstatus: 1) }

    it "does not raise — a new unpinned action in a tracked workflow is a skip, not a corrupt lock" do
      expect { engine.relock(workflow_files: [workflow], lockfile: tracked_lockfile) }
        .not_to raise_error
    end
  end

  describe "#relock with multiple new actions in one workflow" do
    let(:body) do
      {
        "findings" => [
          { "workflow" => ".github/workflows/ci.yml", "category" => "onboarding-required",
            "severity" => "error", "dependency" => "actions/setup-node@v4" },
          { "workflow" => ".github/workflows/ci.yml", "category" => "onboarding-required",
            "severity" => "error", "dependency" => "actions/cache@v4" }
        ]
      }
    end

    before { stub_subprocess(stdout: JSON.generate(body), exitstatus: 1) }

    it "counts the skipped workflow once" do
      allow(Dependabot.logger).to receive(:info)
      engine.relock(workflow_files: [workflow], lockfile: lockfile)

      expect(Dependabot.logger).to have_received(:info).with(/skipped 1 un-onboarded workflow/)
    end
  end

  describe "#relock on a corrupt/unreadable lockfile (exit 2, empty stdout)" do
    # Current CLI contract: a lockfile
    # that exists but cannot be parsed — malformed YAML, or a dependencies entry
    # missing a required key — is no longer silently swallowed to empty on the
    # headless `update` path. It fails loud: exit 2, empty stdout, file untouched.
    # That lands in our exit>1 → EngineError branch, NOT a parsed empty result.
    before do
      stub_subprocess(
        stdout: "",
        exitstatus: 2,
        stderr: "lockfile is unreadable: .github/workflows/actions.lock: " \
                "missing required action field \"owner_id\""
      )
    end

    it "raises EngineError, not a parsed empty result" do
      expect { engine.relock(workflow_files: [workflow], lockfile: lockfile) }
        .to raise_error(
          Dependabot::GithubActions::Lockfile::EngineError,
          /failed \(exit 2\).*lockfile is unreadable/m
        )
    end
  end

  describe "#relock with onboarding-required AND a genuine blocker (exit 1)" do
    let(:body) do
      {
        "updated" => [], "workflows" => [],
        "findings" => [
          { "workflow" => ".github/workflows/b.yml", "category" => "onboarding-required",
            "severity" => "error", "detail" => "not tracked" },
          { "category" => "impostor-commit", "severity" => "error",
            "dependency" => "actions/checkout@v6", "detail" => "locked SHA not reachable" }
        ]
      }
    end

    before { stub_subprocess(stdout: JSON.generate(body), exitstatus: 1) }

    it "still raises the genuine blocker — a skip never masks a real finding" do
      expect { engine.relock(workflow_files: [workflow], lockfile: lockfile) }
        .to raise_error(Dependabot::GithubActions::Lockfile::UnresolvableDependency, %r{actions/checkout@v6})
    end
  end

  describe "#relock on a fix-mode happy path that auto-fixed a tracked bump (exit 0)" do
    # The load-bearing Dependabot case, reproduced against the real binary: a
    # tracked workflow whose `uses:` ref was bumped surfaces a `ref-changed`
    # (severity:error) finding — but `findings` is the PRE-fix diagnosis, and the
    # exit code is 0 because fix-mode already re-pinned the lock. The engine must
    # NOT treat that auto-fixed finding as a blocker; it must return the re-pinned
    # lock. (Before the exit-code gate, raise_on_findings wrongly raised here.)
    let(:body) do
      {
        "cli_version" => "v0.0.5", "lockfile_version" => "v0.0.2", "valid" => false,
        "findings" => [
          { "workflow" => ".github/workflows/ci.yml", "category" => "ref-changed",
            "severity" => "error", "confidence" => "high",
            "dependency" => "actions/checkout@v5",
            "detail" => "workflow uses ref \"v5\" but lockfile pins \"v4\"" }
        ]
      }
    end

    before { stub_subprocess(stdout: JSON.generate(body), exitstatus: 0) }

    it "does not raise — a pre-fix finding that exit 0 already resolved is not a blocker" do
      expect { engine.relock(workflow_files: [workflow], lockfile: lockfile) }
        .not_to raise_error
    end

    it "returns the re-pinned lock content read back from disk" do
      result = engine.relock(workflow_files: [workflow], lockfile: lockfile)
      expect(result).to eq(lockfile.content)
    end

    it "uses the root fix interface" do
      engine.relock(workflow_files: [workflow], lockfile: lockfile)

      expect(Dependabot::CommandHelpers).to have_received(:capture3_with_timeout).with(
        include(
          described_class.binary_path,
          "--no-onboard",
          "--no-narrow",
          "--no-interactive",
          "--json=findings",
          ".github/workflows/ci.yml"
        )
      )
    end
  end

  describe "#relock when an auto-fixed bump coincides with a refused onboarding (exit 1)" do
    # The second dry-run defect, reproduced against the real binary: ci.yml is a
    # tracked workflow whose checkout ref was bumped v4->v5 (a `ref-changed`,
    # severity:error, that fix-mode RE-PINS on disk), while a sibling NEW workflow
    # b.yml references an unpinned action that --no-onboard refuses. The refusal
    # forces exit 1, but `findings` is the global PRE-fix diagnosis, so it still
    # lists ci.yml's already-resolved `ref-changed` and `stale`. Before this fix,
    # raise_on_findings ran at exit 1 and raised EngineError on the auto-fixed
    # `ref-changed`, killing a perfectly normal Dependabot bump. The mapper now
    # treats fix-mode-resolved categories as non-blocking; only impostor-commit /
    # lockfile-forgery survive. The run must skip b.yml and return the re-pinned lock.
    let(:body) do
      {
        "cli_version" => "v0.0.5", "lockfile_version" => "v0.0.2", "valid" => false,
        "workflows" => [{ "path" => ".github/workflows/ci.yml" }],
        "findings" => [
          { "workflow" => ".github/workflows/ci.yml", "category" => "ref-changed",
            "severity" => "error", "confidence" => "high", "dependency" => "actions/checkout@v5",
            "detail" => "workflow uses ref \"v5\" but lockfile pins \"v4\"" },
          { "workflow" => ".github/workflows/ci.yml", "category" => "stale",
            "severity" => "warning", "dependency" => "actions/checkout@v4",
            "detail" => "lockfile pin no longer referenced by any uses:" },
          { "workflow" => ".github/workflows/b.yml", "category" => "onboarding-required",
            "severity" => "error", "confidence" => "high", "dependency" => "ncipollo/release-action@v1",
            "detail" => "ncipollo/release-action@v1 has no lockfile entry; --no-onboard refuses to add it" }
        ]
      }
    end

    before { stub_subprocess(stdout: JSON.generate(body), exitstatus: 1) }

    it "does not raise — ref-changed/stale are auto-fixed pre-fix diagnoses, not survivors" do
      expect { engine.relock(workflow_files: [workflow], lockfile: lockfile) }
        .not_to raise_error
    end

    it "returns the lock despite the refused onboarding" do
      expect(engine.relock(workflow_files: [workflow], lockfile: lockfile)).to eq(lockfile.content)
    end
  end

  describe "#relock returns the pruned lock the CLI wrote to disk (stale-pin GC)" do
    # The engine is the sole reader of the lock the CLI rewrites: whatever the
    # binary saves to `.github/workflows/actions.lock` is what relock returns.
    # gh-actions-lock prunes a stale pin on a ref bump — after
    # softprops/action-gh-release@v1 -> @v2 the lock lists ONLY @v2, with the
    # orphaned @v1 ref and its `dependencies:` entry GC'd. This was proven
    # credentialed end-to-end through this exact path; here we stub the subprocess
    # to write that pruned lock so core encodes the post-prune read-back contract
    # without a binary or network. The stub captures the chdir CliEngine passes and
    # overwrites the on-disk lock exactly as the real binary would.
    let(:bumped_workflow) do
      Dependabot::DependencyFile.new(
        name: ".github/workflows/release.yml",
        content: "on: push\njobs:\n  r:\n    steps:\n      - uses: softprops/action-gh-release@v2\n"
      )
    end

    let(:stale_lock) do
      Dependabot::DependencyFile.new(
        name: ".github/workflows/actions.lock",
        content: <<~LOCK
          version: 'v0.0.2'
          workflows:
              '.github/workflows/release.yml':
                  - 'softprops/action-gh-release@v1'
          dependencies:
              'softprops/action-gh-release@v1':
                  ref: 'v1'
                  commit: 'sha1-de2c0eb89ae2a093876385947365aca7b0e5f844'
                  owner_id: 2242
                  repo_id: 204253808
        LOCK
      )
    end

    let(:pruned_lock) do
      <<~LOCK
        version: 'v0.0.2'
        workflows:
            '.github/workflows/release.yml':
                - 'softprops/action-gh-release@v2'
        dependencies:
            'softprops/action-gh-release@v2':
                ref: 'v2'
                commit: 'sha1-3bb12739c298aeb8a4eeaf626c5b8d85266b0e65'
                owner_id: 2242
                repo_id: 204253808
      LOCK
    end

    # exit 0 + a pre-fix `stale` finding for the dropped v1 pin — the binary
    # diagnoses v1 as stale, prunes it, and exits clean. (Plus `ref-changed` for
    # the bump itself.) Neither survives auto-fix, so relock must not raise.
    let(:body) do
      {
        "cli_version" => "v0.0.5", "lockfile_version" => "v0.0.2", "valid" => false,
        "findings" => [
          { "workflow" => ".github/workflows/release.yml", "category" => "ref-changed",
            "severity" => "error", "dependency" => "softprops/action-gh-release@v2",
            "detail" => "workflow uses \"v2\" but lockfile pins \"v1\"" },
          { "workflow" => ".github/workflows/release.yml", "category" => "stale",
            "severity" => "warning", "dependency" => "softprops/action-gh-release@v1",
            "detail" => "no workflow references this pin" }
        ]
      }
    end

    before do
      allow(Dependabot::CommandHelpers)
        .to receive(:capture3_with_timeout) do |env_cmd|
          chdir = env_cmd.last[:chdir]
          File.write(File.join(chdir, ".github/workflows/actions.lock"), pruned_lock)
          [JSON.generate(body), "", process_double(0)]
        end
    end

    it "returns only the v2 pin — the stale v1 ref and its SHA are gone" do
      result = engine.relock(workflow_files: [bumped_workflow], lockfile: stale_lock)

      expect(result).to eq(pruned_lock)
      expect(result).not_to include("@v1")
      expect(result).not_to include("de2c0eb89ae2a093876385947365aca7b0e5f844")
      expect(result).to include("@v2")
    end

    it "does not raise — pruned `stale` and `ref-changed` are pre-fix diagnoses at exit 0" do
      expect { engine.relock(workflow_files: [bumped_workflow], lockfile: stale_lock) }
        .not_to raise_error
    end
  end
end
