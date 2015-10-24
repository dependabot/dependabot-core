#!/usr/bin/env ruby

require "./app/workers/dependency_file_fetcher"
require "dotenv"
Dotenv.load

Workers::DependencyFileFetcher.perform_async(
  "repo" => { "language" => "ruby",
              "name" => "gocardless/bump-test" })
