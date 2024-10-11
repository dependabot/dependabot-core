# typed: false
# frozen_string_literal: true

require "dependabot/package_manager"
require "dependabot/dependency_file"

# This module provides some shortcuts for working with our two mock RubyGems packages:
# - https://rubygems.org/gems/dummy-pkg-a
# - https://rubygems.org/gems/dummy-pkg-b
#
module DummyPkgHelpers
  def stub_rubygems_calls
    stub_request(:get, "https://index.rubygems.org/versions")
      .to_return(status: 200, body: fixture("rubygems-index"))

    stub_request(:get, "https://index.rubygems.org/info/dummy-pkg-a")
      .to_return(status: 200, body: fixture("rubygems-info-a"))
    stub_request(:get, "https://rubygems.org/api/v1/versions/dummy-pkg-a.json")
      .to_return(status: 200, body: fixture("rubygems-versions-a.json"))

    stub_request(:get, "https://index.rubygems.org/info/dummy-pkg-b")
      .to_return(status: 200, body: fixture("rubygems-info-b"))
    stub_request(:get, "https://rubygems.org/api/v1/versions/dummy-pkg-b.json")
      .to_return(status: 200, body: fixture("rubygems-versions-b.json"))
  end

  def original_bundler_files(fixture: "bundler", directory: "/")
    bundler_files_for(fixture: fixture, state: "original", directory: directory)
  end

  def updated_bundler_files(fixture: "bundler", directory: "/")
    bundler_files_for(fixture: fixture, state: "updated", directory: directory)
  end

  def bundler_files_for(fixture:, state:, directory: "/")
    [
      Dependabot::DependencyFile.new(
        name: "Gemfile",
        content: fixture("#{fixture}/#{state}/Gemfile"),
        directory: directory
      ),
      Dependabot::DependencyFile.new(
        name: "Gemfile.lock",
        content: fixture("#{fixture}/#{state}/Gemfile.lock"),
        directory: directory
      )
    ]
  end

  def create_temporary_content_directory(fixture:, directory: "/", state: "original")
    tmp_dir = Dir.mktmpdir
    FileUtils.cp_r(File.join("spec", "fixtures", fixture, state, "/."), File.join(tmp_dir, directory))

    # The content directory needs to a repo
    Dir.chdir(tmp_dir) do
      system("git init --initial-branch main . && git add . && git commit --allow-empty -m 'Init'", out: File::NULL)
    end

    tmp_dir
  end

  def updated_bundler_files_hash(fixture: "bundler")
    updated_bundler_files(fixture: fixture).map(&:to_h)
  end

  # Stub PackageManagerBase
  class StubPackageManager < Dependabot::PackageManagerBase
    def initialize(name:, version:, deprecated_versions: [], unsupported_versions: [], supported_versions: [])
      @name = name
      @version = version
      @deprecated_versions = deprecated_versions
      @unsupported_versions = unsupported_versions
      @supported_versions = supported_versions
    end

    attr_reader :name
    attr_reader :version
    attr_reader :deprecated_versions
    attr_reader :unsupported_versions
    attr_reader :supported_versions

    sig { override.returns(T::Boolean) }
    def deprecated?
      # If the version is unsupported, the unsupported error is getting raised separately.
      return false if unsupported?

      deprecated_versions.include?(version)
    end

    sig { override.returns(T::Boolean) }
    def unsupported?
      # Check if the feature flag for Bundler v1 unsupported error is enabled.
      return false unless name == "bundler"

      version < supported_versions.first
    end
  end
end
