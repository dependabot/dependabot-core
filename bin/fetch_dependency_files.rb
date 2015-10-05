$LOAD_PATH << "lib"

require "bumper/boot"
require "bumper/dependency_file_fetchers/ruby_dependency_file_fetcher"

repos = Prius.get(:watched_repos).split(",")
DependencyFileFetchers::RubyDependencyFileFetcher.run(repos)
