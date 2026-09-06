# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "yaml"

require "dependabot/errors"

module Dependabot
  module KotlinToolchain
    module YamlParser
      extend T::Sig

      # Kotlin Toolchain task references use Gradle-style paths such as
      # :module:task or :task. They are valid in Kotlin Toolchain manifests, but
      # Psych rejects them inside flow collections. Replacing only the leading
      # colon keeps every byte offset intact, which lets the YAML editor use
      # Psych's source positions on the original file.
      TASK_REFERENCE = /(^|[\s\[,{]):(?=[A-Za-z0-9_.-]+(?::[A-Za-z0-9_.@+-]+)*(?:[\s\],}]|$))/

      # Under the YAML core schema `version: 3.2` is a Float and `1.10` collapses
      # to 1.1, while dates are rejected by the restricted class loader. Manifest
      # versions and dates are only ever read as text here.
      class ScalarScanner < Psych::ScalarScanner
        extend T::Sig

        TEXT_SCALAR = /\A(?:\d+\.\d+|\d{4}-\d{1,2}-\d{1,2})/

        sig { params(string: String).returns(Object) }
        def tokenize(string)
          return string if string.match?(TEXT_SCALAR)

          super
        end
      end

      sig { params(content: String).returns(String) }
      def self.sanitize(content)
        content.gsub(TASK_REFERENCE) { "#{Regexp.last_match(1)}_" }
      end

      sig { params(content: String, filename: String).returns(Object) }
      def self.load(content, filename:)
        document = Psych.parse(sanitize(content))
        return unless document

        class_loader = Psych::ClassLoader::Restricted.new([], [])
        scanner = ScalarScanner.new(class_loader, parse_symbols: false)
        Psych::Visitors::ToRuby.new(scanner, class_loader).accept(document)
      rescue Psych::Exception => e
        raise Dependabot::DependencyFileNotParseable.new(filename, "#{filename}: #{e.message}")
      end

      sig { params(content: String, filename: String).returns(T.nilable(Psych::Nodes::Document)) }
      def self.parse(content, filename:)
        document = Psych.parse(sanitize(content))
        document || nil
      rescue Psych::Exception => e
        raise Dependabot::DependencyFileNotParseable.new(filename, "#{filename}: #{e.message}")
      end
    end
  end
end
