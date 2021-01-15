# frozen_string_literal: true

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

class ExampleGroupData
  attr_reader :metadata, :fixture_names

  def initialize(metadata)
    @metadata = metadata
    @fixture_names = Set[]
  end

  def explain
    "#{metadata[:full_description]} (#{metadata[:location]}) uses fixtures: #{fixture_names.to_a.join(', ')}"
  end

  def self.key(metadata)
    Digest::SHA256.hexdigest(metadata[:full_description])
  end

  def add_fixture(name)
    @fixture_names << name
  end
end

class LetInspector
  class << self
    attr_accessor :storage
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

    LetInspector.prepend_behavior(self, name) do |metadata|
      # puts name
      # puts caller_locations(1..1).first
      # puts block.source_location

      key = ExampleGroupData.key(metadata)
      data = LetInspector.storage.fetch(key) { ExampleGroupData.new(metadata) }
      if FIXTURE_NAMES.include?(name.to_sym)
        fixture_name = block.call
        data.add_fixture(fixture_name)
      end
      LetInspector.storage[key] = data
    end
  end

  def self.prepend_behavior(scope, method_name)
    original_method = scope.instance_method(method_name)

    scope.__send__(:define_method, method_name) do |*args, &block|
      yield self.class.metadata

      original_method.bind(self).call(*args, &block)
    end
  end
end

RSpec.configure do |c|
  c.after do
    LetInspector.storage.each do |_, data|
      puts data.explain
    end
  end
end
