# frozen_string_literal: true

# This module provides some shortcuts for working with our two mock RubyGems packages:
# - https://rubygems.org/gems/dummy-pkg-a
# - https://rubygems.org/gems/dummy-pkg-b
#
module DummyPkgHelpers
  def stub_rubygems_calls
    stub_request(:get, "https://index.rubygems.org/versions").
      to_return(status: 200, body: fixture("rubygems-index"))

    stub_request(:get, "https://index.rubygems.org/info/dummy-pkg-a").
      to_return(status: 200, body: fixture("rubygems-info-a"))
    stub_request(:get, "https://rubygems.org/api/v1/versions/dummy-pkg-a.json").
      to_return(status: 200, body: fixture("rubygems-versions-a.json"))

    stub_request(:get, "https://index.rubygems.org/info/dummy-pkg-b").
      to_return(status: 200, body: fixture("rubygems-info-b"))
    stub_request(:get, "https://rubygems.org/api/v1/versions/dummy-pkg-b.json").
      to_return(status: 200, body: fixture("rubygems-versions-b.json"))
  end

  def original_bundler_files(fixture: "bundler")
    [
      Dependabot::DependencyFile.new(
        name: "Gemfile",
        content: fixture("#{fixture}/original/Gemfile"),
        directory: "/"
      ),
      Dependabot::DependencyFile.new(
        name: "Gemfile.lock",
        content: fixture("#{fixture}/original/Gemfile.lock"),
        directory: "/"
      )
    ]
  end

  def updated_bundler_files(fixture: "bundler")
    [
      Dependabot::DependencyFile.new(
        name: "Gemfile",
        content: fixture("#{fixture}/updated/Gemfile"),
        directory: "/"
      ),
      Dependabot::DependencyFile.new(
        name: "Gemfile.lock",
        content: fixture("#{fixture}/updated/Gemfile.lock"),
        directory: "/"
      )
    ]
  end

  def updated_bundler_files_hash(fixture: "bundler")
    updated_bundler_files(fixture: fixture).map(&:to_h)
  end
end
