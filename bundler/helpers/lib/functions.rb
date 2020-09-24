module Functions

  def self.bundler_version
    Bundler::VERSION
  end

  def self.parsed_gemfile(gemfile_name:, dir:)
    ::Bundler.instance_variable_set(:@root, Pathname.new(Dir.pwd))

    ::Bundler::Definition.build(gemfile_name, nil, {}).
      dependencies.select(&:current_platform?).
      reject { |dep| dep.source.is_a?(::Bundler::Source::Gemspec) }.
      map(&method(:serialize_bundler_dependency))
  end

  def self.parsed_gemspec(gemspec_name:, dir:)
    ::Bundler.instance_variable_set(:@root, dir)
    ::Bundler.load_gemspec_uncached(gemspec_name).
      dependencies.
      map(&method(:serialize_bundler_dependency))
  end

  def self.serialize_bundler_dependency(dependency)
    {
      name: dependency.name,
      requirement: dependency.requirement,
      groups: dependency.groups,
      source: dependency.source,
    }
  end

  def self.vendor_cache_dir(dir:)
    # Set the path for path gemspec correctly
    ::Bundler.instance_variable_set(:@root, dir)
    ::Bundler.app_cache
  end
end
