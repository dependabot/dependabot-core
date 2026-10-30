# typed: false
# frozen_string_literal: true

require "fileutils"
require "open3"
require "spec_helper"
require "tmpdir"
require "dependabot/github_actions/containing_branch_finder"
require "dependabot/github_actions/repository_cloner"

RSpec.describe Dependabot::GithubActions::RepositoryCloner do
  describe ".clone" do
    subject(:clone_repository) { described_class.clone(url: url, path: path, bare: bare) }

    let(:bare) { false }
    let(:url) { "https://github.com/actions/setup-node" }
    let(:workspace) { Dir.mktmpdir("repository-cloner") }
    let(:path) { File.join(workspace, "setup-node") }

    around do |example|
      dir = workspace
      example.run
    ensure
      FileUtils.rm_rf(dir)
    end

    def clone_failure(message)
      Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: message, error_context: {})
    end

    shared_examples "a partial clone with a full clone fallback" do |partial_options, full_options|
      let(:partial_clone_command) { "git clone #{partial_options} #{url} #{path}" }
      let(:full_clone_command) { "git clone #{full_options} #{url} #{path}" }

      context "when the partial clone succeeds" do
        before do
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("")
        end

        it "clones commits only and does not run a full clone" do
          clone_repository

          expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
            partial_clone_command,
            fingerprint: "git clone #{partial_options} <url> <path>"
          )
          expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command).with(full_clone_command, any_args)
        end
      end

      context "when the partial clone fails" do
        before do
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
            .with(partial_clone_command, any_args) do
              FileUtils.mkdir_p(File.join(path, "objects"))
              raise clone_failure("fatal: the remote end hung up unexpectedly\n")
            end
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
            .with(full_clone_command, any_args) do
              raise "partial clone directory was not removed" if Dir.exist?(path)

              ""
            end
          allow(Dependabot.logger).to receive(:warn)
        end

        it "removes the partial clone and falls back to a full clone" do
          clone_repository

          expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
            full_clone_command,
            fingerprint: "git clone #{full_options} <url> <path>"
          )
          expect(Dependabot.logger).to have_received(:warn).with(/Partial clone failed, falling back to a full clone/)
        end
      end

      context "when both the partial and the full clone fail" do
        before do
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

        it "raises the full clone error with a fingerprint without the URL or the temporary path" do
          expect { clone_repository }.to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed) do |error|
            expect(error.sentry_context[:fingerprint]).to eq(["git clone #{full_options} <url> <path>"])
          end
        end
      end
    end

    it_behaves_like "a partial clone with a full clone fallback",
                    "--no-checkout --filter=tree:0 --no-recurse-submodules",
                    "--no-recurse-submodules"

    context "with a bare clone" do
      let(:bare) { true }

      it_behaves_like "a partial clone with a full clone fallback",
                      "--bare --filter=tree:0 --no-recurse-submodules",
                      "--bare --no-recurse-submodules"
    end

    context "with a real repository" do
      let(:source_path) { File.join(workspace, "source") }
      let(:url) { "file://#{source_path}" }

      def git(*args, chdir:, env: {})
        stdout, stderr, status = Open3.capture3(
          env, "git", "-c", "user.name=Dependabot", "-c", "user.email=dependabot@example.com", *args, chdir: chdir
        )
        raise "git #{args.join(' ')} failed: #{stderr}" unless status.success?

        stdout.strip
      end

      before do
        FileUtils.mkdir_p(source_path)
        git("init", "--initial-branch=main", chdir: source_path)
        git("config", "uploadpack.allowFilter", "true", chdir: source_path)
        File.write(File.join(source_path, "action.yml"), "name: first\n")
        git("add", ".", chdir: source_path)
        git("commit", "-m", "first", chdir: source_path, env: { "GIT_COMMITTER_DATE" => "2024-01-02T03:04:05Z" })
        git("tag", "-a", "v1.0.0", "-m", "v1.0.0", chdir: source_path)
        File.write(File.join(source_path, "action.yml"), "name: second\n")
        git("commit", "-am", "second", chdir: source_path)
        git("switch", "--create", "releases/v1", "HEAD~1", chdir: source_path)
        File.write(File.join(source_path, "action.yml"), "name: release\n")
        git("commit", "-am", "release", chdir: source_path)
        git("switch", "main", chdir: source_path)
      end

      # The source is removed after cloning, so the lookup passes only if the partial clone
      # already holds everything it reads.
      it "keeps enough history to find the branch that contains a commit that is not a branch tip" do
        first_commit = git("rev-parse", "main~1", chdir: source_path)
        release_commit = git("rev-parse", "releases/v1", chdir: source_path)

        clone_repository
        FileUtils.rm_rf(source_path)

        expect(git("config", "remote.origin.partialclonefilter", chdir: path)).to eq("tree:0")
        expect(Dir.children(path)).to eq([".git"])
        Dir.chdir(path) do
          expect(Dependabot::GithubActions::ContainingBranchFinder.find(first_commit)).to eq("main")
          expect(Dependabot::GithubActions::ContainingBranchFinder.find(release_commit)).to eq("releases/v1")
        end
      end

      context "with a bare clone" do
        let(:bare) { true }

        it "keeps the tag and commit dates used for cooldown" do
          tag_date = git("for-each-ref", "--format=%(creatordate:iso)", "refs/tags/v1.0.0", chdir: source_path)
          first_commit = git("rev-parse", "main~1", chdir: source_path)

          clone_repository
          expect(git("config", "remote.origin.partialclonefilter", chdir: path)).to eq("tree:0")

          # Tag dates are read from the clone alone.
          FileUtils.mv(source_path, "#{source_path}.offline")
          expect(git("for-each-ref", "--format=%(creatordate:iso)", "refs/tags/v1.0.0", chdir: path)).to eq(tag_date)
          FileUtils.mv("#{source_path}.offline", source_path)

          # `git show` also reads the commit's root tree, which a tree:0 clone fetches on demand.
          expect(git("show", "--no-patch", "--format=%cd", "--date=iso", first_commit, chdir: path))
            .to eq("2024-01-02 03:04:05 +0000")
        end
      end
    end
  end
end
