# typed: strict
# frozen_string_literal: true

require "fileutils"
require "open3"
require "shellwords"
require "spec_helper"
require "tmpdir"
require "dependabot/github_actions/containing_branch_finder"
require "dependabot/github_actions/repository_cloner"

RSpec.describe Dependabot::GithubActions::RepositoryCloner do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(T::Boolean) }
  let(:bare) { false }
  sig { returns(String) }
  let(:partial_options) { "--no-checkout --filter=tree:0 --no-recurse-submodules" }
  sig { returns(String) }
  let(:full_options) { "--no-recurse-submodules" }
  sig { returns(String) }
  let(:url) { "https://github.com/actions/setup-node" }
  sig { returns(String) }
  let(:workspace) { Dir.mktmpdir("repository-cloner") }
  sig { returns(String) }
  let(:path) { File.join(workspace, "setup-node") }
  # rubocop:enable RSpec/ScatteredLet

  after do
    FileUtils.rm_rf(workspace)
  end

  sig { void }
  def clone_repository
    described_class.clone(url: url, path: path, bare: bare)
  end

  sig { params(options: String).returns(String) }
  def clone_command(options)
    "git clone #{options} #{url} #{path}"
  end

  sig { void }
  def stub_partial_clone_failure
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with(clone_command(partial_options), any_args) do
        FileUtils.mkdir_p(File.join(path, "objects"))
        raise Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "fatal: the remote end hung up unexpectedly\n",
          error_context: {}
        )
      end
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with(clone_command(full_options), any_args) do
        raise "partial clone directory was not removed" if Dir.exist?(path)

        ""
      end
    allow(Dependabot.logger).to receive(:warn)
  end

  sig { void }
  def stub_all_clones_failing
    allow(Dependabot::CommandHelpers).to receive(:capture3_with_timeout)
      .with(array_including(/\Agit clone /), any_args)
      .and_return(
        [
          "Cloning into 'dependabot_tmp_dir/actions/setup-node'...\n" \
          "fatal: write error: No space left on device\n",
          "",
          instance_double(Process::Status, success?: false, to_s: "pid 1 exit 128")
        ]
      )
    allow(Dependabot.logger).to receive(:warn)
  end

  sig { void }
  def expect_partial_clone_only
    expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
      clone_command(partial_options),
      fingerprint: "git clone #{partial_options} <url> <path>"
    )
    expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
      .with(clone_command(full_options), any_args)
  end

  sig { void }
  def expect_full_clone_fallback
    expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
      clone_command(full_options),
      fingerprint: "git clone #{full_options} <url> <path>"
    )
    expect(Dependabot.logger).to have_received(:warn).with(/Partial clone failed, falling back to a full clone/)
  end

  sig { void }
  def expect_full_clone_error_fingerprint
    expect { clone_repository }.to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed) do |error|
      expect(error.sentry_context[:fingerprint]).to eq(["git clone #{full_options} <url> <path>"])
    end
  end

  context "with a working tree clone" do
    it "clones commits only and does not run a full clone when the partial clone succeeds" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("")

      clone_repository

      expect_partial_clone_only
    end

    it "removes the partial clone and falls back to a full clone when the partial clone fails" do
      stub_partial_clone_failure

      clone_repository

      expect_full_clone_fallback
    end

    it "raises the full clone error with a fingerprint without the URL or the temporary path when both fail" do
      stub_all_clones_failing

      expect_full_clone_error_fingerprint
    end
  end

  context "with a bare clone" do
    # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
    sig { returns(T::Boolean) }
    let(:bare) { true }
    sig { returns(String) }
    let(:partial_options) { "--bare --filter=tree:0 --no-recurse-submodules" }
    sig { returns(String) }
    let(:full_options) { "--bare --no-recurse-submodules" }
    # rubocop:enable RSpec/ScatteredLet

    it "clones commits only and does not run a full clone when the partial clone succeeds" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("")

      clone_repository

      expect_partial_clone_only
    end

    it "removes the partial clone and falls back to a full clone when the partial clone fails" do
      stub_partial_clone_failure

      clone_repository

      expect_full_clone_fallback
    end

    it "raises the full clone error with a fingerprint without the URL or the temporary path when both fail" do
      stub_all_clones_failing

      expect_full_clone_error_fingerprint
    end
  end

  context "with a real repository" do
    # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
    sig { returns(String) }
    let(:source_path) { File.join(workspace, "source") }
    sig { returns(String) }
    let(:url) { "file://#{source_path}" }
    # rubocop:enable RSpec/ScatteredLet

    sig { params(arguments: T::Array[String], chdir: String, env: T::Hash[String, String]).returns(String) }
    def git(arguments, chdir:, env: {})
      git_environment = {
        "GIT_AUTHOR_EMAIL" => "dependabot@example.com",
        "GIT_AUTHOR_NAME" => "Dependabot",
        "GIT_COMMITTER_EMAIL" => "dependabot@example.com",
        "GIT_COMMITTER_NAME" => "Dependabot"
      }.merge(env)
      stdout, stderr, status = Open3.capture3(git_environment, Shellwords.join(["git"] + arguments), chdir: chdir)
      raise "git #{arguments.join(' ')} failed: #{stderr}" unless status.success?

      stdout.strip
    end

    before do
      FileUtils.mkdir_p(source_path)
      git(%w(init --initial-branch=main), chdir: source_path)
      git(%w(config uploadpack.allowFilter true), chdir: source_path)
      File.write(File.join(source_path, "action.yml"), "name: first\n")
      git(%w(add .), chdir: source_path)
      git(%w(commit -m first), chdir: source_path, env: { "GIT_COMMITTER_DATE" => "2024-01-02T03:04:05Z" })
      git(%w(tag -a v1.0.0 -m v1.0.0), chdir: source_path)
      File.write(File.join(source_path, "action.yml"), "name: second\n")
      git(%w(commit -am second), chdir: source_path)
      git(%w(switch --create releases/v1 HEAD~1), chdir: source_path)
      File.write(File.join(source_path, "action.yml"), "name: release\n")
      git(%w(commit -am release), chdir: source_path)
      git(%w(switch main), chdir: source_path)
    end

    # The source is removed after cloning, so the lookup passes only if the partial clone
    # already holds everything it reads.
    it "keeps enough history to find the branch that contains a commit that is not a branch tip" do
      first_commit = git(%w(rev-parse main~1), chdir: source_path)
      release_commit = git(%w(rev-parse releases/v1), chdir: source_path)

      clone_repository
      FileUtils.rm_rf(source_path)

      expect(git(%w(config remote.origin.partialclonefilter), chdir: path)).to eq("tree:0")
      expect(Dir.children(path)).to eq([".git"])
      Dir.chdir(path) do
        expect(Dependabot::GithubActions::ContainingBranchFinder.find(first_commit)).to eq("main")
        expect(Dependabot::GithubActions::ContainingBranchFinder.find(release_commit)).to eq("releases/v1")
      end
    end

    context "with a bare clone" do
      sig { returns(T::Boolean) }
      let(:bare) { true }

      it "keeps the tag and commit dates used for cooldown" do
        tag_date_command = %w(for-each-ref --format=%(creatordate:iso) refs/tags/v1.0.0)
        tag_date = git(tag_date_command, chdir: source_path)
        first_commit = git(%w(rev-parse main~1), chdir: source_path)

        clone_repository
        expect(git(%w(config remote.origin.partialclonefilter), chdir: path)).to eq("tree:0")

        # Tag dates are read from the clone alone.
        FileUtils.mv(source_path, "#{source_path}.offline")
        expect(git(tag_date_command, chdir: path)).to eq(tag_date)
        FileUtils.mv("#{source_path}.offline", source_path)

        # `git show` also reads the commit's root tree, which a tree:0 clone fetches on demand.
        expect(git(["show", "--no-patch", "--format=%cd", "--date=iso", first_commit], chdir: path))
          .to eq("2024-01-02 03:04:05 +0000")
      end
    end
  end
end
