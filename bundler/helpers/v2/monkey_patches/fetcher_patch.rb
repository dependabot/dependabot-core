require "bundler/fetcher"

module Bundler
  module DisableDependencyAPI
    def available?
      return false if remote_uri.host == "rubygems.org"

      super
    end
  end

  module DisableFullIndex
    def available?
      return true if fetch_uri.scheme == "file"
      return false if remote_uri.host == "rubygems.org"

      super
    end
  end
end

Bundler::Fetcher::Dependency.prepend(Bundler::DisableDependencyAPI)
Bundler::Fetcher::Index.prepend(Bundler::DisableFullIndex)
