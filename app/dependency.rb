require "gems"
require "./lib/github"
require "./app/dependency_source_code_finders/ruby"
require "./app/dependency_source_code_finders/node"

class Dependency
  attr_reader :name, :version, :language

  CHANGELOG_NAMES = %w(changelog history news).freeze
  GITHUB_REGEX    = %r{github\.com/(?<repo>[^/]+/[^/]+)/?}
  SOURCE_KEYS     = %w(source_code_uri homepage_uri wiki_uri bug_tracker_uri
                       documentation_uri).freeze

  def initialize(name:, version:, language: nil)
    @name = name
    @version = version
    @language = language
  end

  def github_repo
    return unless language
    return @github_repo if @github_repo_lookup_attempted
    look_up_github_repo
  end

  def github_repo_url
    return unless github_repo
    Github.client.web_endpoint + github_repo
  end

  def changelog_url
    return unless github_repo
    return @changelog_url if @changelog_url_lookup_attempted

    look_up_changelog_url
  end

  private

  def look_up_github_repo
    @github_repo_lookup_attempted = true
    @github_repo = source_code_finder.github_repo
  end

  def look_up_changelog_url
    @changelog_url_lookup_attempted = true

    files = Github.client.contents(github_repo)
    file = files.find { |f| CHANGELOG_NAMES.any? { |w| f.name =~ /#{w}/i } }

    @changelog_url = file.nil? ? nil : file.html_url
  rescue Octokit::NotFound
    @changelog_url = nil
  end

  def source_code_finder
    @source_code_finder ||=
      begin
        finder_class =
          case language
          when "ruby" then DependencySourceCodeFinders::Ruby
          when "node" then DependencySourceCodeFinders::Node
          else raise "Invalid language #{language}"
          end

        finder_class.new(dependency_name: name)
      end
  end
end
