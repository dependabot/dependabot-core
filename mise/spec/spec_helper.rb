# typed: true
# frozen_string_literal: true

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

def mise_ls(tool = nil)
  command = ["mise", "ls", "--current", "--no-global", "--json"]
  command += ["--", tool] if tool

  receive(:run_shell_command).with(
    command,
    stderr_to_stdout: false,
    env: hash_including("MISE_YES" => "1", "MISE_SAFE" => "1", "MISE_OVERRIDE_CONFIG_FILENAMES" => anything)
  )
end

def mise_ls_remote(tool)
  receive(:run_shell_command).with(
    ["mise", "ls-remote", "--json", "--", tool],
    stderr_to_stdout: false,
    env: hash_including("MISE_YES" => "1", "MISE_SAFE" => "1", "MISE_OVERRIDE_CONFIG_FILENAMES" => anything)
  )
end
