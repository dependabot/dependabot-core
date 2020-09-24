module Functions

  def self.bundler_version
    Bundler::VERSION
  end

  def self.parse_gemfile(gemfile_name:, dir:)
    ::Bundler.instance_variable_set(:@root, Pathname.new(Dir.pwd))

    ::Bundler::Definition.build(gemfile_name, nil, {}).
      dependencies.select(&:current_platform?).
      reject { |dep| dep.source.is_a?(::Bundler::Source::Gemspec) }.
      map do |dep|
        {
          name: dep.name,
          requirement: dep.requirement,
          groups: dep.groups,
          source: dep.source,
        }
      end
  end
end
