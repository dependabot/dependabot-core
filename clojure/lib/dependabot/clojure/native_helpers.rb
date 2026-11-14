# typed: strong
# frozen_string_literal: true

require "digest"
require "sorbet-runtime"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/dependency_file"

module Dependabot
  module Clojure
    module NativeHelpers
      extend T::Sig

      # One dependency declaration, with the position of its version string.
      # Rows and columns are 1-based; end_col is exclusive.
      class Declaration < T::Struct
        const :name, String
        const :version, String
        const :groups, T::Array[String]
        const :classifier, T.nilable(String)
        const :row, Integer
        const :col, Integer
        const :end_row, Integer
        const :end_col, Integer
      end

      class ParseResult < T::Struct
        const :declarations, T::Array[Declaration]
        const :repositories, T::Array[String]
      end

      @parse_cache = T.let({}, T::Hash[String, ParseResult])

      # Parses project.clj or deps.edn without evaluating it. Results are cached
      # by content, so the update checker can reuse them for every dependency.
      sig { params(file: Dependabot::DependencyFile).returns(ParseResult) }
      def self.parse(file)
        content = T.must(file.content)
        cache_key = Digest::SHA256.hexdigest("#{file.name}\0#{content}")
        @parse_cache[cache_key] ||= run_parse(file, content)
      end

      sig { params(file: Dependabot::DependencyFile, content: String).returns(ParseResult) }
      def self.run_parse(file, content)
        result = T.cast(
          SharedHelpers.run_helper_subprocess(
            command: "java -jar #{helper_path}",
            function: "parse",
            args: { file_name: file.name, content: content }
          ),
          T::Hash[String, T.anything]
        )

        ParseResult.new(
          declarations: T.cast(result.fetch("dependencies"), T::Array[T::Hash[String, T.anything]])
                         .map { |dep| build_declaration(dep) },
          repositories: T.cast(result.fetch("repositories"), T::Array[String])
        )
      rescue SharedHelpers::HelperSubprocessFailed => e
        raise Dependabot::DependencyFileNotParseable.new(file.path, e.message) if e.error_class == "ParseError"

        raise
      end
      private_class_method :run_parse

      sig { params(dep: T::Hash[String, T.anything]).returns(Declaration) }
      def self.build_declaration(dep)
        Declaration.new(
          name: T.cast(dep.fetch("name"), String),
          version: T.cast(dep.fetch("version"), String),
          groups: T.cast(dep.fetch("groups"), T::Array[String]),
          classifier: T.cast(dep["classifier"], T.nilable(String)),
          row: T.cast(dep.fetch("row"), Integer),
          col: T.cast(dep.fetch("col"), Integer),
          end_row: T.cast(dep.fetch("end_row"), Integer),
          end_col: T.cast(dep.fetch("end_col"), Integer)
        )
      end
      private_class_method :build_declaration

      sig { returns(String) }
      def self.helper_path
        clean_path(File.join(native_helpers_root, "clojure/clojure-helper.jar"))
      end

      sig { returns(String) }
      def self.native_helpers_root
        default_path = File.join(__dir__, "../../../helpers/install-dir")
        ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", default_path)
      end

      sig { params(path: String).returns(String) }
      def self.clean_path(path)
        Pathname.new(path).cleanpath.to_path
      end
    end
  end
end
