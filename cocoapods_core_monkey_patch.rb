# frozen_string_literal: true

require "cocoapods-core"

# This isn't pretty, but speeds specs up a lot (and avoids network calls) whilst
# we're waiting for https://github.com/CocoaPods/Core/pull/374 to be included
# in a release.
#
# It's only required in spec/spec_helper.rb

module Pod
  module GitHub
    def self.repo_id_from_url(url)
      url[%r{github.com[/:]([^/]*/(?:(?!\.git)[^/])*)\.*}, 1]
    end
  end
end

module Pod
  class Source
    def update(show_output)
      return [] if unchanged_github_repo?
      super
    end

    def unchanged_github_repo?
      url = repo_git(%w(config --get remote.origin.url))
      return unless url =~ /github.com/
      !Pod::GitHub.modified_since_commit(url, git_commit_hash)
    end
  end
end
