#!/usr/bin/env ruby

require "aws-sdk"
require "dotenv"
Dotenv.load

Aws.config.update(endpoint: "http://localhost:4568")

#####################
# Delete old queues #
#####################

sqs = Aws::SQS::Client.new
sqs.list_queues.queue_urls.each { |url| sqs.delete_queue(queue_url: url) }

#####################
# Create new queues #
#####################

# Fake SQS doesn't yet support setting attributes at queue creation time, so
# we have to create each queue in two steps.

queue = sqs.create_queue(queue_name: "bump-repos_to_fetch_files_for")
sqs.set_queue_attributes(queue_url: queue.queue_url,
                         attributes: { "VisibilityTimeout" => "5" })

queue = sqs.create_queue(queue_name: "bump-dependency_files_to_parse")
sqs.set_queue_attributes(queue_url: queue.queue_url,
                         attributes: { "VisibilityTimeout" => "5" })

queue = sqs.create_queue(queue_name: "bump-dependencies_to_check")
sqs.set_queue_attributes(queue_url: queue.queue_url,
                         attributes: { "VisibilityTimeout" => "5" })

queue = sqs.create_queue(queue_name: "bump-dependencies_to_update")
sqs.set_queue_attributes(queue_url: queue.queue_url,
                         attributes: { "VisibilityTimeout" => "60" })

queue = sqs.create_queue(queue_name: "bump-updated_dependency_files")
sqs.set_queue_attributes(queue_url: queue.queue_url,
                         attributes: { "VisibilityTimeout" => "10" })
