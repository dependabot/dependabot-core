# frozen_string_literal: true

module ProjectFixtures
  class Finder
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

    LET_NAMES = MANIFEST_FIXTURE_LETS | LOCKFILE_FIXTURE_LETS
    FILE_NAMES = %i(files dependency_files).freeze

    TRACKED_LETS = LET_NAMES | FILE_NAMES

    def self.example_group
      RSpec::Core::ExampleGroup
    end

    def example_group.let(name, &block)
      super(name, &block)

      let_location = caller_locations.first

      ProjectFixtures::Finder.prepend_behavior(self, name) do |metadata, evaluated_block|
        key = ExampleGroupData.key(metadata)
        data = ProjectFixtures::Finder.storage.fetch(key) { ExampleGroupData.new(metadata) }

        if TRACKED_LETS.include?(name.to_sym)
          let = Let.new(
            name: name,
            file: File.realpath(let_location.path),
            line: let_location.lineno,
            block_result: evaluated_block
          )

          data.add_let(let)
        end
        ProjectFixtures::Finder.storage[key] = data
      end
    end

    def self.prepend_behavior(scope, method_name)
      original_method = scope.instance_method(method_name)

      scope.__send__(:define_method, method_name) do |*args, &block|
        evaluated_block = original_method.bind(self).call(*args, &block)
        yield self.class.metadata, evaluated_block

        original_method.bind(self).call(*args, &block)
      end
    end

    Let = Struct.new(:name, :file, :line, :block_result, keyword_init: true)

    class ExampleGroupData
      attr_reader :metadata, :lets

      def initialize(metadata)
        @metadata = metadata
        @lets = Set[]
      end

      def self.key(metadata)
        Digest::SHA256.hexdigest(metadata[:full_description])
      end

      def add_let(let)
        @lets << let
      end

      def project_name
        fixture_names.map { |f| File.basename(f, File.extname(f)) }.join("_")
      end

      def fixture_names
        lets.to_a.select { |l| LET_NAMES.include?(l.name) }.map(&:block_result)
      end

      def files
        @files ||= lets.select { |n| FILE_NAMES.include?(n.name) }.flat_map do |let|
          let.block_result.select { |f| f if f.is_a?(Dependabot::DependencyFile) }
        end
      end
    end
  end
end
