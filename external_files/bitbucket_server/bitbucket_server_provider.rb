require_relative "bitbucket_server"

class BitbucketServerProvider
  attr_accessor :provider, :repo, :directory, :branch, :commit,
                :hostname, :api_endpoint, :client

  def initialize(repo:, directory: nil, branch: nil, commit: nil,
                   hostname: nil, api_endpoint: nil, credentials: nil)
    @provider = "bitbucket_server"
    @repo = repo
    @directory = directory
    @branch = branch
    @commit = commit
    @hostname = hostname
    @api_endpoint = api_endpoint
    @client = BitbucketServerClient.new(credentials: credentials, source: self)
  end

  def url
    "https://" + hostname + "/" + repo
  end

  def url_with_directory
    return url if [nil, ".", "/"].include?(directory)

    path = Pathname.new(File.join("src/#{branch || 'default'}", directory)).
           cleanpath.to_path
    url + "/" + path
  end
end
