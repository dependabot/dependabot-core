#!/usr/bin/env ruby
# frozen_string_literal: true

# This script searches for open issues in the dependabot/dependabot-core repository
# where a job ID (10-digit number) is mentioned in the opening comment.

require "net/http"
require "json"
require "uri"

REPO_OWNER = "dependabot"
REPO_NAME = "dependabot-core"
GITHUB_API_TOKEN = ENV["GITHUB_TOKEN"] || ENV["DEPENDABOT_TEST_ACCESS_TOKEN"]

# Pattern to match job IDs - a 10-digit number
JOB_ID_PATTERN = /\b\d{10}\b/

def fetch_issues(page = 1, per_page = 100)
  uri = URI("https://api.github.com/repos/#{REPO_OWNER}/#{REPO_NAME}/issues")
  uri.query = URI.encode_www_form(
    state: "open",
    per_page: per_page,
    page: page
  )

  request = Net::HTTP::Get.new(uri)
  request["Accept"] = "application/vnd.github+json"
  request["Authorization"] = "Bearer #{GITHUB_API_TOKEN}" if GITHUB_API_TOKEN
  request["X-GitHub-Api-Version"] = "2022-11-28"

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end

  if response.code == "200"
    JSON.parse(response.body)
  else
    puts "Error fetching issues: #{response.code} #{response.message}"
    puts response.body
    []
  end
end

def find_issues_with_job_ids
  issues_with_job_ids = []
  page = 1
  loop do
    puts "Fetching page #{page}..."
    issues = fetch_issues(page)
    break if issues.empty?

    issues.each do |issue|
      # Skip pull requests
      next if issue["pull_request"]

      body = issue["body"] || ""
      if body.match?(JOB_ID_PATTERN)
        issues_with_job_ids << {
          number: issue["number"],
          title: issue["title"],
          url: issue["html_url"],
          job_ids: body.scan(JOB_ID_PATTERN).uniq
        }
      end
    end

    # GitHub API returns at most 100 results per page
    break if issues.length < 100

    page += 1
  end

  issues_with_job_ids
end

# Main execution
puts "Searching for open issues with job IDs in #{REPO_OWNER}/#{REPO_NAME}..."
issues = find_issues_with_job_ids

if issues.empty?
  puts "No issues found with job IDs."
else
  puts "\nFound #{issues.length} issue(s) with job IDs:"
  puts

  # Create output text file with URLs
  File.open("issues_with_jobids.txt", "w") do |file|
    issues.each do |issue|
      puts "##{issue[:number]}: #{issue[:title]}"
      puts "  URL: #{issue[:url]}"
      puts "  Job IDs: #{issue[:job_ids].join(', ')}"
      puts

      file.puts issue[:url]
    end
  end

  puts "\nURLs saved to issues_with_jobids.txt"
end
