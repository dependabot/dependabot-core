# typed: false
# frozen_string_literal: true

require "open3"
require "rbconfig"
require "spec_helper"
require "dependabot/metadata_finders/base/commit_response_parser"

RSpec.describe Dependabot::MetadataFinders::Base::CommitResponseParser do
  it "loads and parses provider responses independently" do
    lib_path = File.expand_path("../../../../lib", __dir__)
    script = <<~RUBY
      require "dependabot/metadata_finders/base/commit_response_parser"

      parser = Dependabot::MetadataFinders::Base::CommitResponseParser.new(
        source_url: "https://example.com"
      )

      agent = Sawyer::Agent.new("https://api.github.com")
      github_commit = Sawyer::Resource.new(agent, sha: "github-sha")
      raise unless parser.github_commit_sha(github_commit) == "github-sha"

      gitlab_commit = Gitlab::ObjectifiedHash.new("id" => "gitlab-sha")
      raise unless parser.gitlab_string(gitlab_commit, "id", "commit") == "gitlab-sha"
    RUBY

    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I", lib_path, "-e", script)

    expect(stderr).to eq("")
    expect(status).to be_success
  end
end
