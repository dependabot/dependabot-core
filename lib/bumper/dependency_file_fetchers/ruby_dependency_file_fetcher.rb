require "prius"

# TODO: Move me to main app file so it's clear I happen at boot time
Prius.load(:github_token)

module DependencyFileFetchers
  class RubyDependencyFileFetcher
  end
end
