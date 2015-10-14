require "gems"
require "./lib/github"

class Dependency
  attr_reader :name, :version

  CHANGELOG_NAMES = %w(changelog history)

  def initialize(name:, version:)
    @name = name
    @version = version
  end

  def url(fetch: -> (name) { nil })
    @url ||= fetch.(name)
  end
end
