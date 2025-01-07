# typed: false
# frozen_string_literal: true

require "fileutils"
require "tmpdir"

require "spec_helper"
require "dependabot/workspace/git"

RSpec.describe Dependabot::Workspace::Git do
  subject(:workspace) { described_class.new(repo_contents_path) }

  let(:repo_contents_path) { build_tmp_repo("simple", tmp_dir_path: Dir.tmpdir) }

  around do |example|
    Dir.chdir(repo_contents_path) { example.run }
    FileUtils.rm_rf(repo_contents_path)
  end

  specify "its initial state" do
    expect(workspace.change_attempts).to be_empty
    expect(workspace.changes).to be_empty
    expect(workspace.failed_change_attempts).to be_empty
    expect(workspace).not_to be_changed
  end

  describe "#initial_head_sha", :focus do # rubocop:disable RSpec/Focus
    let(:head_sha) { File.read(File.join(repo_contents_path, ".git", "refs", "heads", "master")).strip }

    it "is the initial HEAD sha before any change attempts" do
      expect(workspace.initial_head_sha).to eq(head_sha)
    end

    context "with warnings from git rev-parse" do
      before do
        # Git no longer allows you to create a branch or symbolic ref named HEAD
        # so we need to manually hack a HEAD ref file to ensure that no warnings
        # are included in the output of git rev-parse
        FileUtils.cp(
          File.join(repo_contents_path, ".git", "refs", "heads", "master"),
          File.join(repo_contents_path, ".git", "refs", "heads", "HEAD")
        )
      end

      it "is the initial HEAD sha before any change attempts" do
        expect(workspace.initial_head_sha).to eq(head_sha)
      end
    end
  end

  describe "#to_patch" do
    it "returns an empty string by default" do
      expect(workspace.to_patch).to eq("")
    end

    context "when there are changes" do
      before do
        workspace.change("rspec") { `echo 'gem "rspec", "~> 3.12.0", group: :test' >> Gemfile` }
        workspace.store_change("rspec")
        workspace.change("timecop") { `echo 'gem "timecop", "~> 0.9.6", group: :test' >> Gemfile` }
        workspace.store_change("rspec")
      end

      it "returns the diff of all changes" do
        expect(workspace.changes.size).to eq(2)
        expect(workspace.to_patch).to end_with(
          <<~DIFF
             gem "activesupport", ">= 6.0.0"
            +gem "rspec", "~> 3.12.0", group: :test
            +gem "timecop", "~> 0.9.6", group: :test
          DIFF
        )
      end

      context "when there are failed change attempts" do
        before do
          workspace.change("fail") do
            `echo 'gem "fail"' >> Gemfile`
            raise "uh oh"
          end
        rescue RuntimeError
          # nop
        end

        it "returns the diff of all changes excluding failed change attempts" do
          expect(workspace.changes.size).to eq(2)
          expect(workspace.failed_change_attempts.size).to eq(1)
          expect(workspace.to_patch).to end_with(
            <<~DIFF
               gem "activesupport", ">= 6.0.0"
              +gem "rspec", "~> 3.12.0", group: :test
              +gem "timecop", "~> 0.9.6", group: :test
            DIFF
          )
        end
      end
    end
  end

  describe "#change" do
    context "when the #change is successful" do
      it "captures the change" do
        workspace.change("timecop") do
          `echo 'gem "timecop", "~> 0.9.6", group: :test' >> Gemfile`
        end
        expect(workspace.failed_change_attempts).to be_empty
        expect(workspace.changes.size).to eq(0)
        expect(workspace).to be_changed
      end
    end

    context "when an error occurs" do
      it "captures the failed change attempt" do
        expect do
          workspace.change("timecop") do
            `echo 'gem "timecop", "~> 0.9.6", group: :test' >> Gemfile`
            raise "uh oh"
          end
        end.to raise_error(RuntimeError, "uh oh")

        expect(workspace.changes).to be_empty
        expect(workspace).not_to be_changed
        expect(workspace.failed_change_attempts.size).to eq(1)
        expect(workspace.change_attempts.size).to eq(1)
        expect(workspace.change_attempts.first.id).to eq(`git rev-parse refs/stash`.strip)
        expect(workspace.change_attempts.first.diff).to end_with(
          <<~DIFF
             gem "activesupport", ">= 6.0.0"
            +gem "timecop", "~> 0.9.6", group: :test
          DIFF
        )
        expect(workspace.change_attempts.first.memo).to eq("timecop")
        expect(workspace.change_attempts.first.error).not_to be_nil
        expect(workspace.change_attempts.first.error.message).to eq("uh oh")
        expect(workspace.change_attempts.first).to be_error
        expect(workspace.change_attempts.first).not_to be_success
      end

      context "when there are untracked/ignored files" do
        # See: common/spec/fixtures/projects/simple/.gitignore

        before do
          workspace.change("fail") do
            `echo 'gem "fail"' >> Gemfile`
            `echo 'untracked output' >> untracked-file.txt`
            `echo 'ignored output' >> ignored-file.txt`
            raise "uh oh"
          end
        rescue RuntimeError
          # nop
        end

        it "captures the untracked/ignored files" do
          expect(workspace.failed_change_attempts.size).to eq(1)
          expect(workspace.failed_change_attempts.first.diff).to include(
            <<~DIFF
               gem "activesupport", ">= 6.0.0"
              +gem "fail"
            DIFF
          )
          expect(workspace.failed_change_attempts.first.diff).to include(
            "diff --git a/ignored-file.txt b/ignored-file.txt",
            "diff --git a/untracked-file.txt b/untracked-file.txt"
          )
        end
      end
    end
  end

  describe "#reset!" do
    it "clears change attempts, drops stashes, and resets HEAD to initial_head_sha" do
      workspace.change("rspec") { `echo 'gem "rspec", "~> 3.12.0", group: :test' >> Gemfile` }
      workspace.store_change("rspec")
      workspace.change("timecop") { `echo 'gem "timecop", "~> 0.9.6", group: :test' >> Gemfile` }
      workspace.store_change("timecop")

      begin
        workspace.change do
          `echo 'gem "fail1"' >> Gemfile`
          raise "uh oh"
        end
      rescue RuntimeError
        # nop
      end

      begin
        workspace.change do
          `echo 'gem "fail2"' >> Gemfile`
          raise "uh oh"
        end
      rescue RuntimeError
        # nop
      end

      initial_head_sha = workspace.initial_head_sha

      expect(workspace.change_attempts.size).to eq(4)
      expect(workspace.change_attempts.last.id).to eq(`git rev-parse refs/stash`.strip)

      expect(workspace.changes.size).to eq(2)
      expect(workspace).to be_changed
      expect(workspace.changes.last.id).to eq(`git rev-parse HEAD`.strip)
      expect(`git log --format='%H' #{initial_head_sha}..HEAD | wc -l`.strip).to eq("2")

      expect(workspace.failed_change_attempts.size).to eq(2)
      expect(workspace.failed_change_attempts.last.id).to eq(`git rev-parse refs/stash`.strip)
      expect(`git stash list | wc -l`.strip).to eq("2")

      workspace.reset!

      expect(workspace.change_attempts).to be_empty
      expect(workspace.failed_change_attempts).to be_empty
      expect(workspace.changes).to be_empty
      expect(workspace).not_to be_changed
      expect(`git rev-parse HEAD`.strip).to eq(initial_head_sha)
      expect(`git log --format='%H' #{initial_head_sha}..HEAD | wc -l`.strip).to eq("0")
      expect(`git stash list | wc -l`.strip).to eq("0")
    end
  end

  describe "#store_change" do
    context "when there are no changes to store" do
      it "returns nil and doesn't add any changes to the workspace" do
        workspace.store_change("noop")

        expect(workspace).not_to be_changed
        expect(workspace.changes).to be_empty
      end
    end

    context "when there are changes to ignored files" do
      # See: common/spec/fixtures/projects/simple/.gitignore

      it "returns nil and doesn't add any changes to the workspace" do
        workspace.change { `echo "ignore me" >> ignored-file.txt` }
        workspace.store_change("modify ignored file")
        workspace.change { `mkdir -p ignored-dir && echo "ignore me" >> ignored-dir/file.txt` }
        workspace.store_change("modify file in ignored directory")

        expect(workspace).not_to be_changed
        expect(workspace.changes).to be_empty
      end
    end

    context "when there are changes to store" do
      it "stores the changes correctly" do
        workspace.change("timecop") do
          `echo 'gem "timecop", "~> 0.9.6", group: :test' >> Gemfile`
        end
        workspace.store_change("Update timecop")
        expect(workspace.failed_change_attempts).to be_empty
        expect(workspace.changes.size).to eq(1)
        expect(workspace).to be_changed
        expect(workspace.change_attempts.size).to eq(1)
        expect(workspace.change_attempts.first.id).to eq(`git rev-parse HEAD`.strip)
        expect(workspace.change_attempts.first.diff).to end_with(
          <<~DIFF
             gem "activesupport", ">= 6.0.0"
            +gem "timecop", "~> 0.9.6", group: :test
          DIFF
        )
        expect(workspace.change_attempts.first.memo).to eq("Update timecop")
        expect(workspace.change_attempts.first.error).to be_nil
        expect(workspace.change_attempts.first).not_to be_error
        expect(workspace.change_attempts.first).to be_success
      end
    end
  end
end
