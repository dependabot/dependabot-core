# frozen_string_literal: true

module Gem
  class Specification
    WHITELISTED_CLASSES = %w(
      Symbol
      Time
      Date
      Gem::Dependency
      Gem::Platform
      Gem::Requirement
      Gem::Specification
      Gem::Version
      Gem::Version::Requirement
    ).freeze

    WHITELISTED_SYMBOLS = %w(
      development
      runtime
    ).freeze

    def self.from_yaml(input)
      input = normalize_yaml_input input
      spec = Psych.safe_load(
        input,
        WHITELISTED_CLASSES,
        WHITELISTED_SYMBOLS,
        true
      )

      raise Gem::EndOfYAMLException if spec && spec.class == FalseClass

      unless Gem::Specification === spec # rubocop:disable Style/CaseEquality
        raise Gem::Exception, "YAML data doesn't evaluate to gem specification"
      end

      spec.specification_version ||= NONEXISTENT_SPECIFICATION_VERSION
      spec.reset_nil_attributes_to_default

      spec
    end
  end

  class Package
    def read_checksums(gem)
      Gem.load_yaml

      @checksums = gem.seek "checksums.yaml.gz" do |entry|
        Zlib::GzipReader.wrap entry do |gz_io|
          Psych.safe_load(
            gz_io.read,
            Gem::Specification::WHITELISTED_CLASSES,
            Gem::Specification::WHITELISTED_SYMBOLS,
            true
          )
        end
      end
    end
  end
end
