# typed: false
# frozen_string_literal: true

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

def kotlin_wrapper(version, windows: false, sha: "a" * 64)
  if windows
    <<~BAT
      @echo off
      set kotlin_cli_version=#{version}
      set kotlin_cli_sha256=#{sha}
      if not defined KOTLIN_CLI_DOWNLOAD_ROOT set KOTLIN_CLI_DOWNLOAD_ROOT=https://packages.jetbrains.team/maven/p/amper/amper
    BAT
  else
    <<~SH
      #!/bin/sh
      kotlin_cli_version=#{version}
      kotlin_cli_sha256=#{sha}
      KOTLIN_CLI_DOWNLOAD_ROOT="${KOTLIN_CLI_DOWNLOAD_ROOT:-https://packages.jetbrains.team/maven/p/amper/amper}"
    SH
  end
end
