# frozen_string_literal: true

require "fileutils"
require "tmpdir"

require "spec_helper"
require "dependabot/workspace"

RSpec.describe Dependabot::Workspace do
  def init_repo
    `cp -r #{fixture_path}/* #{repo_path}`
    `git init .`
    `git add .`
    `git commit -m 'Initial commit'`
  end

  let(:fixture_path) do
    Pathname.new(File.join(File.dirname(__FILE__), "..", "fixtures", "projects", "simple")).expand_path.to_s
  end

  let(:repo_path) do
    Dir.mktmpdir(nil, "/tmp")
  end

  subject(:workspace) do
    Dependabot::Workspace::Git.new(repo_path)
  end

  around do |example|
    Dir.chdir(repo_path) { example.run }
    FileUtils.rm_rf(repo_path)
  end

  before do
    init_repo
  end

  describe "#initial_head_sha" do
    it "is the initial HEAD sha before any change attempts" do
      expect(workspace.initial_head_sha).to eq(`git rev-parse HEAD`.strip)
    end
  end

  describe "#to_patch" do
    it "returns an empty string by default" do
      expect(workspace.changes).to be_empty
      expect(workspace.to_patch).to eq("")
    end

    context "when there are changes" do
      before do
        workspace.change { `echo 'gem "rspec", "~> 3.12.0", group: :test' >> Gemfile` }
        workspace.change { `echo 'gem "timecop", "~> 0.9.6", group: :test' >> Gemfile` }
      end

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

      context "when there are failed change attempts" do
        before do
          begin
            workspace.change do
              `echo 'fail' >> Gemfile`
              raise "fail"
            end
          rescue RuntimeError
            # nop
          end
        end

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
      end
    end
  end

  describe "#change" do
    context "success" do
      it "captures the change" do
        workspace.change("add timecop dependency") do
          `echo 'gem "timecop", "~> 0.9.6", group: :test' >> Gemfile`
        end
        expect(workspace.failed_change_attempts).to be_empty
        expect(workspace.changes.size).to eq(1)
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
        expect(workspace.change_attempts.first.memo).to eq("add timecop dependency")
        expect(workspace.change_attempts.first.error).to be_nil
        expect(workspace.change_attempts.first.error?).to be_falsy
        expect(workspace.change_attempts.first.success?).to be_truthy
      end
    end

    context "error" do
      it "captures the failed change attempt" do
        expect do
          workspace.change("add timecop dependency") do
            `echo 'gem "timecop", "~> 0.9.6", group: :test' >> Gemfile`
            raise "uh oh"
          end
        end.to raise_error(RuntimeError, "uh oh")

        expect(workspace.changes).to be_empty
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
        expect(workspace.change_attempts.first.memo).to eq("add timecop dependency")
        expect(workspace.change_attempts.first.error).not_to be_nil
        expect(workspace.change_attempts.first.error.message).to eq("uh oh")
        expect(workspace.change_attempts.first.error?).to be_truthy
        expect(workspace.change_attempts.first.success?).to be_falsy
      end
    end
  end
end
