class Dependency
  attr_reader :name, :version

  CHANGELOG_NAMES = %w(changelog history)
  GITHUB_REGEX    = %r{github\.com/(?<repo>[^/]+/[^/]+)/?}
  SOURCE_KEYS     = %w(source_code_uri homepage_uri wiki_uri bug_tracker_uri
                       documentation_uri)

  def initialize(name:, version:)
    @name = name
    @version = version
  end

  def github_repo
    return @github_repo if @github_repo_lookup_attempted
    look_up_github_repo
  end

  def github_repo_url
    return unless github_repo
    Github.client.web_endpoint + github_repo
  end

  def changelog_url
    return unless github_repo
    files = Github.client.contents(github_repo)
    file = files.find { |f| CHANGELOG_NAMES.any? { |w| f.name =~ /#{w}/i } }

    file.nil? ? nil : file.url
  end

  private

  def look_up_github_repo
    @github_repo_lookup_attempted = true

    potential_source_urls =
      Gems.info(name).select { |key, _| SOURCE_KEYS.include?(key) }.values
    source_url = potential_source_urls.find { |url| url =~ GITHUB_REGEX }

    @github_repo = source_url.nil? ? nil : source_url.match(GITHUB_REGEX)[:repo]
  end
end
