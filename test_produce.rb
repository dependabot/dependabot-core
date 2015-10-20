require "./app/workers/dependency_file_fetcher"
require "dotenv"
Dotenv.load

# TBC

Workers::DependencyFileFetcher.perform_async(
  "repo" => { "language" => "ruby",
              "name" => "gocardless/bump-test" })
