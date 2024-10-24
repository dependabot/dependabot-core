# typed: true
# frozen_string_literal: true

module Dependabot
  module MavenOSV
    module Utils
      module SourceFinder
        def self.from_repo(repo_contents_path:)
          repo_base_url = SharedHelpers.run_shell_command("git config --get remote.origin.url", cwd: repo_contents_path)
          sha = SharedHelpers.run_shell_command("git rev-parse HEAD", cwd: repo_contents_path)
          Source.from_url("#{repo_base_url}/tree/#{sha}")
        end
      end
    end
  end
end
