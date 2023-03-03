# frozen_string_literal: true

require "fileutils"
require "tmpdir"

require "spec_helper"
require "dependabot/workspace"

RSpec.describe Dependabot::Workspace do
  let(:repo_contents_path) { build_tmp_repo("simple", tmp_dir_path: Dir.tmpdir) }

  subject(:workspace) { Dependabot::Workspace::Git.new(repo_contents_path) }

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

  describe "#initial_head_sha" do
    it "is the initial HEAD sha before any change attempts" do
      expect(workspace.initial_head_sha).to eq(`git rev-parse HEAD`.strip)
    end
  end

  describe "#to_patch" do
    it "returns an empty string by default" do
      expect(workspace.to_patch).to eq("")
    end

    context "when there are changes" do
      before do
        workspace.change("rspec") { `echo 'gem "rspec", "~> 3.12.0", group: :test' >> Gemfile` }
        workspace.change("timecop") { `echo 'gem "timecop", "~> 0.9.6", group: :test' >> Gemfile` }
      end

      # rubocop:disable Layout/TrailingWhitespace
      it "returns the diff of all changes" do
        expect(workspace.changes.size).to eq(2)
        expect(workspace.to_patch).to eq(
          <<~DIFF
            diff --git a/Gemfile b/Gemfile
            index 0e6bb68..7a464a8 100644
            --- a/Gemfile
            +++ b/Gemfile
            @@ -1,3 +1,5 @@
             source "https://rubygems.org"
             
             gem "activesupport", ">= 6.0.0"
            +gem "rspec", "~> 3.12.0", group: :test
            +gem "timecop", "~> 0.9.6", group: :test
          DIFF
        )
      end
      # rubocop:enable Layout/TrailingWhitespace

      context "when there are failed change attempts" do
        before do
          workspace.change("fail") do
            `echo 'gem "fail"' >> Gemfile`
            raise "uh oh"
          end
        rescue RuntimeError
          # nop
        end

        # rubocop:disable Layout/TrailingWhitespace
        it "returns the diff of all changes excluding failed change attempts" do
          expect(workspace.changes.size).to eq(2)
          expect(workspace.failed_change_attempts.size).to eq(1)
          expect(workspace.to_patch).to eq(
            <<~DIFF
              diff --git a/Gemfile b/Gemfile
              index 0e6bb68..7a464a8 100644
              --- a/Gemfile
              +++ b/Gemfile
              @@ -1,3 +1,5 @@
               source "https://rubygems.org"
               
               gem "activesupport", ">= 6.0.0"
              +gem "rspec", "~> 3.12.0", group: :test
              +gem "timecop", "~> 0.9.6", group: :test
            DIFF
          )
        end
        # rubocop:enable Layout/TrailingWhitespace
      end
    end
  end

  describe "#change" do
    context "on success" do
      # rubocop:disable Layout/TrailingWhitespace
      it "captures the change" do
        workspace.change("timecop") do
          `echo 'gem "timecop", "~> 0.9.6", group: :test' >> Gemfile`
        end
        expect(workspace.failed_change_attempts).to be_empty
        expect(workspace.changes.size).to eq(1)
        expect(workspace).to be_changed
        expect(workspace.change_attempts.size).to eq(1)
        expect(workspace.change_attempts.first.id).to eq(`git rev-parse HEAD`.strip)
        expect(workspace.change_attempts.first.diff).to eq(
          <<~DIFF
            diff --git a/Gemfile b/Gemfile
            index 0e6bb68..77d166d 100644
            --- a/Gemfile
            +++ b/Gemfile
            @@ -1,3 +1,4 @@
             source "https://rubygems.org"
             
             gem "activesupport", ">= 6.0.0"
            +gem "timecop", "~> 0.9.6", group: :test
          DIFF
        )
        expect(workspace.change_attempts.first.memo).to eq("timecop")
        expect(workspace.change_attempts.first.error).to be_nil
        expect(workspace.change_attempts.first.error?).to be_falsy
        expect(workspace.change_attempts.first.success?).to be_truthy
      end
      # rubocop:enable Layout/TrailingWhitespace
    end

    context "on error" do
      # rubocop:disable Layout/TrailingWhitespace
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
        expect(workspace.change_attempts.first.diff).to eq(
          <<~DIFF
            diff --git a/Gemfile b/Gemfile
            index 0e6bb68..77d166d 100644
            --- a/Gemfile
            +++ b/Gemfile
            @@ -1,3 +1,4 @@
             source "https://rubygems.org"
             
             gem "activesupport", ">= 6.0.0"
            +gem "timecop", "~> 0.9.6", group: :test
          DIFF
        )
        expect(workspace.change_attempts.first.memo).to eq("timecop")
        expect(workspace.change_attempts.first.error).not_to be_nil
        expect(workspace.change_attempts.first.error.message).to eq("uh oh")
        expect(workspace.change_attempts.first.error?).to be_truthy
        expect(workspace.change_attempts.first.success?).to be_falsy
      end
      # rubocop:enable Layout/TrailingWhitespace

      # rubocop:disable Layout/TrailingWhitespace
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
          expect(workspace.failed_change_attempts.first.diff).to eq(
            <<~DIFF
              diff --git a/Gemfile b/Gemfile
              index 0e6bb68..958f479 100644
              --- a/Gemfile
              +++ b/Gemfile
              @@ -1,3 +1,4 @@
               source "https://rubygems.org"
               
               gem "activesupport", ">= 6.0.0"
              +gem "fail"
              diff --git a/ignored-file.txt b/ignored-file.txt
              new file mode 100644
              index 0000000..85d9237
              --- /dev/null
              +++ b/ignored-file.txt
              @@ -0,0 +1 @@
              +ignored output
              diff --git a/untracked-file.txt b/untracked-file.txt
              new file mode 100644
              index 0000000..b65afb0
              --- /dev/null
              +++ b/untracked-file.txt
              @@ -0,0 +1 @@
              +untracked output
            DIFF
          )
        end
      end
      # rubocop:enable Layout/TrailingWhitespace
    end
  end

  describe "#reset!" do
    it "clears change attempts, drops stashes, and resets HEAD to initial_head_sha" do
      workspace.change("rspec") { `echo 'gem "rspec", "~> 3.12.0", group: :test' >> Gemfile` }
      workspace.change("timecop") { `echo 'gem "timecop", "~> 0.9.6", group: :test' >> Gemfile` }

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
end
