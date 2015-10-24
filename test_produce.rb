#!/usr/bin/env ruby

require "aws-sdk"
require "./app/workers/dependency_file_fetcher"
require "dotenv"
Dotenv.load

Aws.config.update(endpoint: "http://localhost:4568")

sqs = Aws::SQS::Client.new
sqs.list_queues.queue_urls.each { |url| sqs.delete_queue(queue_url: url) }

sqs.create_queue(queue_name: "bump-repos_to_fetch_files_for")
sqs.create_queue(queue_name: "bump-dependency_files_to_parse")
sqs.create_queue(queue_name: "bump-dependencies_to_check")
sqs.create_queue(queue_name: "bump-dependencies_to_update")
sqs.create_queue(queue_name: "bump-updated_dependency_files")

Workers::DependencyFileFetcher.perform_async(
  "repo" => { "language" => "ruby",
              "name" => "gocardless/bump-test" })
