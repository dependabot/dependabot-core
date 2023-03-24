# TODO: PR Comment
# I started with the original file straight from our VMW repo. From there,
# I added functionality to support file fetching and PR creation.
#
# Question: Should we maintain the separation of functionality between client,
# file fetcher, and PR creation?

# frozen_string_literal: true

require "dependabot/shared_helpers"
require "excon"
require_relative "pull_request_creator"

# TODO: PR Comment: Usually, classes like this are built up into nested namespaces.
# For example, the original implementation had this as Dependabot::Clients::BitbucketServer.
# I removed these wrappers because I wanted to emphasize that this are not part of the
# dependabot-core framework.
class BitbucketServerClient
  class NotFound < StandardError; end

  class Unauthorized < StandardError; end

  class Forbidden < StandardError; end

  ##########
  # Client #
  ##########

  # TODO: NOTE REPO_NAMESPACE in all the paths. Needs a way to get project namespace.
  # Provides the namespace for APIs. Example: "projects/UEM" or "users/ctiede"
  REPO_NAMESPACE = ENV["BITBUCKET_REPO_NAMESPACE"]

  attr_reader :source

  def initialize(credentials:, source:)
    @credentials = credentials
    @source = source
    @auth_header = auth_header_for(credentials&.fetch("token", nil))
  end

  def fetch_commit(repo, branch)
    # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp225
    path = "#{REPO_NAMESPACE}/repos/#{repo}/commits/#{branch}"
    response = get(base_url + path)
    JSON.parse(response.body).fetch("id")
  end

  def fetch_default_branch(repo)
    # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp213
    path = "#{REPO_NAMESPACE}/repos/#{repo}/branches/default"
    response = get(base_url + path)
    JSON.parse(response.body).fetch("id").sub("refs/heads/", "")
  end

  # TODO: PR Comment: This method was pulled from file_fetchers but I think it makes more sense here.
  def repo_contents(repo, path, commit)
    response = fetch_repo_contents(
      repo,
      commit,
      path
    )

    response.map do |file|
      type = case file.fetch("type")
               when "FILE" then "file"
               when "DIRECTORY" then "dir"
               else raise "Unsupported file type"
             end

      OpenStruct.new(
        name: File.basename(file.fetch("path").fetch("name")),
        path: file.fetch("path"),
        type: type,
        size: file.fetch("size", 0)
      )
    end
  end

  def fetch_repo_contents(repo, commit = nil, path = nil)
    raise "Commit is required if path provided!" if commit.nil? && path

    # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp216
    api_path = "#{REPO_NAMESPACE}/repos/#{repo}/browse?at=#{commit}&limit=100"
    response = get(base_url + api_path)
    JSON.parse(response.body).fetch("children").fetch("values")
  end

  def fetch_file_contents(repo, commit, path)
    # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp362
    encoded_path = path.gsub(" ", "%20").
      gsub("AW.Core.Api.Model.Mappers.Test.csproj",
           "AW.Core.API.Model.Mappers.Test.csproj")
    if path != encoded_path
      # TODO: tiedec understand this
      raise("Why is this necessary?\n" \
            "  Started with '#{path}'\n" \
            "  converted to '#{encoded_path}'")
    end

    path = "#{REPO_NAMESPACE}/repos/#{repo}/raw/#{encoded_path}?at=#{commit}"
    response = get(base_url + path)

    response.body
  end

  def commits(repo, branch_name = nil)
    # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp222
    commits_path = "#{REPO_NAMESPACE}/repos/#{repo}/commits?since=#{branch_name}"
    next_page_url = base_url + commits_path
    paginate({ "next" => next_page_url })
  end

  def branch(repo, branch_name)
    # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp209
    branch_path = "#{REPO_NAMESPACE}/repos/#{repo}/branches?filterText=#{branch_name}"
    response = get(base_url + branch_path)
    branches = JSON.parse(response.body).fetch("values")

    raise "More then one branches found" if branches.length > 1

    branches.first
  end

  def pull_requests(repo, source_branch, target_branch)
    # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp294
    pr_path = "#{REPO_NAMESPACE}/repos/#{repo}/pull-requests?state=ALL"
    next_page_url = base_url + pr_path
    pull_requests = paginate({ "next" => next_page_url })

    pull_requests unless source_branch && target_branch

    pull_requests.select do |pr|
      pr_source_branch = pr.fetch("fromRef").fetch("id").sub("refs/heads/", "")
      pr_target_branch = pr.fetch("toRef").fetch("id").sub("refs/heads/", "")

      pr_source_branch == source_branch && pr_target_branch == target_branch
    end
  end

  def create_commit(repo, branch_name, base_commit, commit_message, files, _author)
    # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp218
    branch = self.branch(repo, branch_name)
    if branch.nil?
      source_branch = fetch_default_branch(repo)
      source_commit_id = base_commit
    else
      source_branch = branch_name
      source_commit_id = branch.fetch("latestCommit")
    end

    files.each do |file|
      multipart_data = excon_multipart_form_data(
        {
          message: commit_message, # TODO: Format markup in commit message
          branch: branch_name,
          sourceCommitId: source_commit_id,
          content: file.content,
          sourceBranch: source_branch
        }
      )

      commit_path = "#{REPO_NAMESPACE}/repos/#{repo}/browse/#{file.name}"
      response = put(base_url + commit_path, multipart_data.fetch("body"), multipart_data.fetch("header_value"))

      brand_details = JSON.parse(response.body)
      next if !brand_details.fetch("errors", []).empty?

      source_commit_id = brand_details.fetch("id")
      source_branch = brand_details.fetch("displayId")
    end
  end

  # rubocop:disable Metrics/ParameterLists
  def create_pull_request(repo, pr_name, source_branch, target_branch,
                          pr_description, _labels, _work_item = nil)
    content = {
      title: pr_name,
      description: pr_description,
      state: "OPEN",
      fromRef: {
        id: source_branch
      },
      toRef: {
        id: target_branch
      }
    }

    pr_path = "#{REPO_NAMESPACE}/repos/#{repo}/pull-requests"
    post(base_url + pr_path, content.to_json)
  end

  # rubocop:enable Metrics/ParameterLists
  def tags(repo)
    # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp398
    raise "Not tested"

    path = "#{REPO_NAMESPACE}/repos/#{repo}/tags?limit=100"
    response = get(base_url + path)

    JSON.parse(response.body).fetch("values")
  end

  def compare(repo, previous_tag, new_tag)
    raise "Not tested"

    # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp398
    path = "#{REPO_NAMESPACE}/repos/#{repo}/compare/changes?from=#{previous_tag}&to=#{new_tag}"
    response = get(base_url + path)

    JSON.parse(response.body).fetch("values")
  end

  def get(url)
    make_request("get", url, nil, "application/json")
  end

  def post(url, body, content_type = "application/json")
    make_request("post", url, body, content_type)
  end

  def put(url, body, content_type = "application/json")
    make_request("put", url, body, content_type)
  end

  def auth_header_for(token)
    return {} unless token

    { "Authorization" => "Bearer #{token}" }
  end

  def excon_multipart_form_data(parameters)
    body = ""
    boundary = SecureRandom.hex(4)

    parameters.map do |key, value|
      next if value.nil?

      body += "--#{boundary}" + Excon::CR_NL
      body += "Content-Disposition: form-data; name=\"#{key}\"" + Excon::CR_NL
      body += "Content-Type: text/plain" + Excon::CR_NL
      body += Excon::CR_NL
      body += value + Excon::CR_NL
    end

    body += "--#{boundary}--" + Excon::CR_NL

    {
      "header_value" => "multipart/form-data; boundary=\"#{boundary}\"",
      "body" => body
    }
  end

  # TODO: PR Comment: The following methods were adapted from pull_request_creator/pr_name_prefixer.rb
  def dependabot_email
    # TODO: update this to a better default
    "dependency-bot@vmware.com"
  end

  def commit_author_email(commit)
    commit.fetch("author").fetch("emailAddress")
  end

  def last_dependabot_commit_message
    @recent_commit_messages ||= commits(source.repo)

    @recent_commit_messages.
      find { |c| commit_author_email(c) == dependabot_email }&.
      fetch("message", nil)&.
      strip
  end

  def recent_commit_messages
    @recent_commit_messages ||= commits(source.repo)

    @recent_commit_messages.
      reject { |c| commit_author_email(c) == dependabot_email }.
      filter_map { |c| c.fetch("message", nil) }.
      reject { |m| m.start_with?("Merge") }.
      map(&:strip)
  end

  # TODO: PR Comment: This was adapted from pull_request_creator.rb
  def create_pr(opts)
    BitbucketServerPullRequestCreator.new(
      source: opts[:source],
      branch_name: opts[:branch_name],
      base_commit: opts[:base_commit],
      credentials: opts[:credentials],
      files: opts[:files],
      commit_message: opts[:message]&.commit_message,
      pr_description: opts[:message]&.pr_message,
      pr_name: opts[:message]&.pr_name,
      author_details: opts[:author_details],
      labeler: nil,
      work_item: opts[:provider_metadata]&.fetch(:work_item, nil)
    )
  end

  # TODO: PR Comment: Adapted from pull_request_creator/message_builder/metadata_presenter.rb
  def source_provider_supports_html?
    false
  end

  # TODO: PR Comment: End of code adapted from other modules.

  private

  def make_request(method, url, body = nil, content_type = "application/json")
    response = Excon.method(method).call(
      url,
      body: body,
      user: credentials&.fetch("username", nil),
      password: credentials&.fetch("password", nil),
      idempotent: false,
      **Dependabot::SharedHelpers.excon_defaults(
        headers: auth_header.merge(
          {
            "Content-Type" => content_type
          }
        )
      )
    )
    raise Unauthorized if response.status == 401
    raise Forbidden if response.status == 403
    # TODO: Understand the need to remove NotFound.
    # During file fetch, nuget_config_files tries to fetch
    # VMware.UEM.CodeGen/NuGet.config but this file does not exist.
    # (Using repo https://stash.air-watch.com/users/ctiede/repos/dbot_test/browse)
    # raise NotFound if response.status == 404

    response
  end

  # Takes a hash with optional `values` and `next` fields
  # Returns an enumerator.
  #
  # Can be used a few ways:
  # With GET:
  #     paginate ({"next" => url})
  # or
  #     paginate(JSON.parse(get(url).body))
  #
  # With POST (for endpoints that provide POST methods for long query parameters)
  #     response = post(url, body)
  #     first_page = JSON.parse(repsonse.body)
  #     paginate(first_page)
  def paginate(page)
    start = 0
    limit = 100
    uri_template = page.fetch("next")

    Enumerator.new do |yielder|
      loop do
        page.fetch("values", []).each { |value| yielder << value }
        break if page.fetch("isLastPage", false)

        uri = URI(uri_template)
        uri.query = [uri.query, "start=#{start}&limit=#{limit}"].compact.join("&")
        next_page_url = uri.to_s

        page = JSON.parse(get(next_page_url).body)
        page["next"] = uri_template # preserve uri template

        start = page.fetch("nextPageStart") if page.key?("nextPageStart") && !page.fetch("nextPageStart").nil?
      end
    end
  end

  attr_reader :auth_header
  attr_reader :credentials

  def base_url
    uri = URI(@source.api_endpoint)
    uri.path = uri.path + (uri.path.end_with?("/") ? "" : "/")
    uri.to_s
  end
end
