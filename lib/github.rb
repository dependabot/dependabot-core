require "constants"
require "octokit"

module Github
  def self.client
    @client ||= Octokit::Client.new(access_token: Constants::GITHUB_TOKEN)
  end
end
