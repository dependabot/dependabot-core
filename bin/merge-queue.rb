#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

module MergeQueue
  extend self

  def add(*pr_list)
    git!("fetch", "origin", "main")

    unless git?("checkout", "origin/merge-train")
      git("checkout", "-b", "merge-train", "origin/main")
      new_merge_train = true
    end

    pr_list.each do |pr|
      gh!("pr", "checkout", pr)
      pr_branch, _ = git("rev-parse", "--abbrev-ref", "HEAD")
      git!("checkout", "merge-train")
      git!("merge", "--ff", "--no-edit", pr_branch.strip)
    end

    git!("push", "origin", "merge-train")

    if new_merge_train
      gh!("pr", "create", "--title", "Current Merge Train", "--body", ":steam_locomotive:", "--repo", "dependabot/dependabot-core")
    end
  end

  private

  def gh!(*cmd)
    run_cmd!("gh", *cmd)
  end

  def git!(*cmd)
    run_cmd!("git", *cmd)
  end

  def git?(*cmd)
    _, status = git(*cmd)

    status.success?
  end

  def git(*cmd)
    run_cmd("git", *cmd)
  end

  def run_cmd!(*cmd)
    output, status = run_cmd(*cmd)
    raise output unless status.success?
  end

  def run_cmd(*cmd)
    puts cmd.join(" ") if ENV["VERBOSE"]
    output, status = Open3.capture2e(*cmd)
    puts output if ENV["VERBOSE"]
    [output, status]
  end
end

MergeQueue.add(*ARGV)
