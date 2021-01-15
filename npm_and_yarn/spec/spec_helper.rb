# frozen_string_literal: true

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

class ProjectFixtureBuilder
  class << self
    attr_accessor :storage, :current_group
  end

  self.storage = {}

  MANIFEST_FIXTURE_LETS = %i(
    manifest_fixture_name
  ).freeze

  LOCKFILE_FIXTURE_LETS = %i(
    npm_lockfile_fixture_name
    npm_lock_fixture_name
    npm_shrinkwrap_fixture_name
    yarn_lock_fixture_name
    yarn_lockfile_fixture_name
  ).freeze

  FIXTURE_NAMES = MANIFEST_FIXTURE_LETS | LOCKFILE_FIXTURE_LETS

  def self.example_group
    RSpec::Core::ExampleGroup
  end

  def example_group.let(name, &block)
    super(name, &block)

    ProjectFixtureBuilder.prepend_behavior(self, name) do |metadata|
      # puts name
      # puts caller_locations(1..1).first
      # puts block.source_location

      key = ExampleGroupData.key(metadata)
      data = ProjectFixtureBuilder.storage.fetch(key) { ExampleGroupData.new(metadata) }
      if FIXTURE_NAMES.include?(name.to_sym)
        fixture_name = block.call
        data.add_fixture_name(fixture_name)
      end
      ProjectFixtureBuilder.current_group = data
      ProjectFixtureBuilder.storage[key] = data
    end
  end

  def self.prepend_behavior(scope, method_name)
    original_method = scope.instance_method(method_name)

    scope.__send__(:define_method, method_name) do |*args, &block|
      yield self.class.metadata

      original_method.bind(self).call(*args, &block)
    end
  end

  class ExampleGroupData
    attr_reader :metadata, :fixture_names, :fixture_paths

    def initialize(metadata)
      @metadata = metadata
      @fixture_names = Set[]
      @fixture_paths = Set[]
    end

    def explain
      msg = String.new("#{metadata[:full_description]} (#{metadata[:location]}) uses fixtures: #{fixture_names.to_a.join(', ')}\n")
      fixture_paths.each do |path|
        msg << "\ncp #{path} #{new_project_folder}"
      end

      msg << "\n\nAdd `let(:project_name) { \"#{project_name}\" }` to the #{metadata[:description]} block"

      msg
    end

    def self.key(metadata)
      Digest::SHA256.hexdigest(metadata[:full_description])
    end

    def add_fixture_name(name)
      @fixture_names << name
    end

    def add_fixture_path(path)
      @fixture_paths << path
    end

    def new_project_folder
      "npm_and_yarn/spec/fixtures/projects/#{project_name}"
    end

    def project_name
      @fixture_names.to_a.map { |f| File.basename(f, File.extname(f)) }.join("-")
    end
  end
end

RSpec.configure do |c|
  c.after do
    ProjectFixtureBuilder.storage.each do |_, data|
      puts data.explain
    end
  end
end
