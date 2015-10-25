#!/usr/bin/env ruby

require "./app/workers/dependency_file_fetcher"
require "./lib/github"
require "highline/import"
require "dotenv"
Dotenv.load

repo = ask("Which repo would you like to bump dependencies for? ") do |question|
  question.validate = lambda { |repo_name|
    begin
      Github.client.repository(repo_name)
      true
    rescue Octokit::NotFound
      false
    end
  }

  question.responses[:invalid_type] =
    "Could not access that repo. Make sure you use the format "\
    "'gocardless/bump', and that your GitHub token has read/write "\
    "access to the given repo."
end

language = choose do |menu|
  menu.index = :none
  menu.header = "Which language would you like to bump dependencies for?"
  menu.choices(:ruby, :node)
end

Workers::DependencyFileFetcher.
  perform_async("repo" => { "language" => language, "name" => repo })

say "Great success - a job has been added to the SQS queue to fetch the "\
    "#{language} dependency files for #{repo}."
