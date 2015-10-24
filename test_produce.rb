#!/usr/bin/env ruby

require "./app/workers/dependency_file_fetcher"
require "highline/import"
require "dotenv"
Dotenv.load

repo = ask "Which repo would you like to bump dependencies for? "

Workers::DependencyFileFetcher.perform_async(
  "repo" => { "language" => "ruby", "name" => repo }
)

say "Great success - a job has been added to the SQS queue to fetch the "\
    "Ruby dependency files for #{repo}."
