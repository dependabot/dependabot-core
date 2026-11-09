# typed: strong
# frozen_string_literal: true

require "pathname"
require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/dependency_graphers/base"
require "dependabot/python/pip_compile_file_matcher"
require "dependabot/python/shared_file_fetcher"

module Dependabot
  module Python
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      # Splits a directory of requirements files (pip / pip-compile) into one manifest group per "layer".
      #
      # Python is the reported case of "layered requirements": a single directory can hold multiple
      # independent requirements files (e.g. base-requirements.txt, test-requirements.txt) cross-linked
      # with `-r`/`-c`.
      #
      # Each 'layer' is its own manifest and must get its own snapshot, rather than the whole
      # directory collapsing onto the first `.txt` alphabetically.
      class RequirementsLayers
        extend T::Sig

        # Regex patterns for detecting Python requirements / dependencies .txt manifest variants.
        # Used to filter out unrelated .txt files (e.g. README-style notes, tool output, etc.) from being
        # treated as pip manifests.

        # Matches "requirements" preceded by a hyphen, period, underscore, start-of-string, or slash,
        # followed by non-whitespace chars and ".txt".
        # Examples: requirements.txt, requirements.prod.txt, requirements/production.txt
        REQUIREMENTS_TXT_REGEX = %r{(?:[-._]|^|/)requirements[^\s]*\.txt$}i

        # More lenient: matches "require" at the start of the filename or after a hyphen/period/underscore/
        # slash delimiter, with an optional hyphen/underscore/slash suffix. The leading delimiter prevents
        # matching "require" as a substring of another word (e.g. "prequire.txt", "acquire.txt").
        # Examples: require.txt, require-test.txt, py3-require.txt, pyenv_require_e2e.txt
        REQUIRE_TXT_REGEX = %r{(?:[-._]|^|/)require(?:[-_/][^\s.]*)?\.txt$}i

        # Matches "dependencies" / "dependency" preceded by a hyphen, period, underscore,
        # start-of-string, or slash, followed by non-whitespace chars and ".txt".
        # Examples: dependencies.txt, my-dependencies.txt, dependencies/python/ansible-lint.txt
        DEPENDENCIES_TXT_REGEX = %r{(?:[-._]|^|/)dependenc(?:y|ies)[^\s]*\.txt$}i

        # More lenient: matches "depend" / "depends" at the start of the filename or after a hyphen/period/
        # underscore/slash delimiter, with an optional hyphen/underscore/slash suffix. The leading delimiter
        # prevents matching "depend" as a substring of another word (e.g. "codependent.txt").
        # Examples: depend.txt, depends.txt, depend-test.txt, py3-depends.txt
        DEPEND_TXT_REGEX = %r{(?:[-._]|^|/)depend(?:s)?(?:[-_/][^\s.]*)?\.txt$}i

        # Whether a .txt filename looks like a real pip manifest rather than an unrelated .txt file.
        sig { params(path: String).returns(T::Boolean) }
        def self.manifest_txt_filename?(path)
          path.match?(REQUIREMENTS_TXT_REGEX) ||
            path.match?(REQUIRE_TXT_REGEX) ||
            path.match?(DEPENDENCIES_TXT_REGEX) ||
            path.match?(DEPEND_TXT_REGEX)
        end

        # Resolves the sibling paths a requirements file references via `-r`/`-c`, returning repo-relative
        # cleanpaths (matching fetched DependencyFile names). Single home for reference resolution, shared by the
        # grapher's bystander filter and the layering group builder so reference-syntax handling never drifts.
        #
        # Reuses SharedFileFetcher's reference regexes so callers keep exactly the children the file fetcher pulled in.
        sig { params(file: Dependabot::DependencyFile).returns(T::Array[String]) }
        def self.referenced_paths(file)
          content = file.content
          return [] if content.nil?

          current_dir = File.dirname(file.name)
          referenced =
            content.scan(Dependabot::Python::SharedFileFetcher::CHILD_REQUIREMENT_REGEX).flatten +
            content.scan(Dependabot::Python::SharedFileFetcher::CONSTRAINT_REGEX).flatten

          referenced.map do |path|
            resolved = current_dir == "." ? path : File.join(current_dir, path)
            Pathname.new(resolved).cleanpath.to_path
          end
        end

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        # Builds one manifest group per requirements layer. A layer's primary is its compiled `.txt` (the
        # most specific file, akin to a lockfile) when present, otherwise its `.in`. The primary and its paired
        # `.in`/`.txt` are parsed as the layer's manifests. Constraints files and siblings referenced via `-r`/`-c`
        # join as support files, so the parser only reads them through those references.
        sig { returns(T::Array[Dependabot::DependencyGraphers::ManifestGroup]) }
        def groups
          layer_primaries.map do |primary|
            Dependabot::DependencyGraphers::ManifestGroup.new(
              primary: primary,
              files: files_for_layer(primary)
            )
          end
        end

        # Marks support files on the parser and has it parse only from the rest. A directory that forms a single
        # layer is parsed whole rather than per group, so it takes that layer's marking.
        sig { params(parser: Dependabot::FileParsers::Base).void }
        def prepare_parser!(parser)
          layers = groups
          if layers.one?
            layer_files = T.must(layers.first).files.to_h { |f| [f.name, f] }
            parser.dependency_files.map! { |f| layer_files.fetch(f.name, f) }
          end
          parser.options[:requirement_roots] = true
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        # The set of files that act as the owning manifest for a layer: every requirements `.txt` that looks
        # like a real manifest, plus any `.in` file that has no compiled `.txt` counterpart.
        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def layer_primaries
          txt_primaries = requirement_family_files.select do |f|
            f.name.end_with?(".txt") && self.class.manifest_txt_filename?(f.name)
          end
          compiled_stems = txt_primaries.map { |f| requirements_stem(f.name) }

          in_primaries = requirement_family_files.select do |f|
            f.name.end_with?(".in") && !compiled_stems.include?(requirements_stem(f.name))
          end

          txt_primaries + in_primaries
        end

        # All the files a single layer needs to parse: the primary, its paired `.in`/`.txt`, constraints
        # files and any `-r`/`-c` referenced siblings.
        sig { params(primary: Dependabot::DependencyFile).returns(T::Array[Dependabot::DependencyFile]) }
        def files_for_layer(primary)
          stem = requirements_stem(primary.name)

          paired = requirement_family_files.select do |f|
            f != primary && requirements_stem(f.name) == stem
          end
          paired += compiled_outputs_of([primary] + paired) - paired

          # When the primary is a compiled `.txt`, the `-r`/`-c` directives live in the paired `.in` files.
          # Constraints files join every layer below, so they are seeded here too: a constraints file
          # that references siblings needs those siblings on disk for the layer to parse.
          referenced = referenced_requirement_files([primary] + paired + constraints_files)

          support = (referenced + constraints_files).uniq - paired - [primary]

          [primary, *paired].map { |f| with_support_flag(f, false) } + support.map { |f| with_support_flag(f, true) }
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def requirement_family_files
          @requirement_family_files ||= T.let(
            dependency_files.select { |f| f.name.end_with?(".txt", ".in") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        # Files named as constraints join every layer so `-c` references to them resolve. A pip-compile output is
        # a lockfile whatever its name, so it stays out and is paired with the layer that owns its `.in` instead.
        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def constraints_files
          requirement_family_files.select do |f|
            File.basename(f.name).include?("constraint") && !pip_compile_matcher.lockfile_for_pip_compile_file?(f)
          end
        end

        # Compiled outputs whose names don't pair them by stem, e.g. `pip-compile requirements.in -o constraints.txt`.
        # Manifest-named outputs are layer primaries in their own right, so they are left out.
        sig do
          params(owners: T::Array[Dependabot::DependencyFile]).returns(T::Array[Dependabot::DependencyFile])
        end
        def compiled_outputs_of(owners)
          owner_names = owners.map(&:name)

          requirement_family_files.select do |f|
            f.name.end_with?(".txt") &&
              !self.class.manifest_txt_filename?(f.name) &&
              owner_names.include?(pip_compile_matcher.manifest_for_pip_compile_lockfile(f)&.name)
          end
        end

        sig { returns(PipCompileFileMatcher) }
        def pip_compile_matcher
          @pip_compile_matcher ||= T.let(
            PipCompileFileMatcher.new(requirement_family_files.select { |f| f.name.end_with?(".in") }),
            T.nilable(PipCompileFileMatcher)
          )
        end

        # Collects sibling files referenced via `-r`/`-c`, walking the chain transitively. Returns only newly
        # discovered files; the seed files are excluded (they are already in the layer).
        #
        # - Seeded from every file in the layer (primary + paired `.in`/`.txt`): a compiled `.txt` primary has
        #   no live `-r`/`-c` directives, so they must be read from the paired `.in`.
        # - Walks the full closure: a referenced file can reference more (e.g. `develop.in` -> `test.in` ->
        #   `base.in`), and the layer needs every sibling on disk to parse in isolation.
        sig { params(seeds: T::Array[Dependabot::DependencyFile]).returns(T::Array[Dependabot::DependencyFile]) }
        def referenced_requirement_files(seeds)
          by_name = requirement_family_files.to_h { |f| [f.name, f] }
          seen = T.let(Set.new(seeds.map(&:name)), T::Set[String])
          queue = T.let(seeds.dup, T::Array[Dependabot::DependencyFile])
          collected = T.let([], T::Array[Dependabot::DependencyFile])

          until queue.empty?
            current = T.must(queue.shift)
            self.class.referenced_paths(current).each do |path|
              next if seen.include?(path)

              seen << path
              referenced = by_name[path]
              next if referenced.nil?

              collected << referenced
              queue << referenced
            end
          end

          collected
        end

        # Returns a copy flagged as a root or a support file, so the parser reads support files only through
        # `-r`/`-c` references. Files from git submodules arrive as support files, so a layer's own manifests are
        # reset to roots. Never mutates the shared DependencyFile.
        sig { params(file: Dependabot::DependencyFile, support: T::Boolean).returns(Dependabot::DependencyFile) }
        def with_support_flag(file, support)
          return file if file.support_file? == support

          Dependabot::DependencyFile.new(
            name: file.name,
            content: file.content,
            directory: file.directory,
            type: file.type,
            support_file: support,
            vendored_file: file.vendored_file,
            symlink_target: file.symlink_target,
            content_encoding: file.content_encoding,
            deleted: file.deleted?,
            operation: file.operation,
            mode: file.mode
          )
        end

        # The stem shared by a pip-compile `.in` and its compiled `.txt` (e.g. "base-requirements").
        sig { params(name: String).returns(String) }
        def requirements_stem(name)
          name.sub(/\.(txt|in)\z/, "")
        end
      end
    end
  end
end
