# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/ecosystem"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/sbt/version"
require "dependabot/sbt/package_manager"
require "dependabot/sbt/language"

module Dependabot
  module Sbt
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"
      require_relative "file_parser/property_value_finder"
      require_relative "file_parser/repositories_finder"

      BUILD_SBT_FILENAME = "build.sbt"
      BUILD_PROPERTIES_FILENAME = "project/build.properties"

      # "org" % "artifact" % "version"  or  "org" %% "artifact" % "version"
      # Optionally followed by % "scope" (e.g. % "test", % "provided")
      LIBRARY_DEP_REGEX = T.let(
        /"(?<group>[^"]+)"\s+(?<op>%%?)\s+"(?<artifact>[^"]+)"\s+%\s+"(?<version>[^"]+)"(?:\s+%\s+"[^"]*")*/,
        Regexp
      )

      # "org" % "artifact" % valName  or  "org" %% "artifact" % valName
      # Also handles dotted references like Object.member
      VAL_REF_DEP_REGEX = T.let(
        /"(?<group>[^"]+)"\s+(?<op>%%?)\s+"(?<artifact>[^"]+)"\s+%\s+(?<val_name>[a-zA-Z_]\w*(?:\.[a-zA-Z_]\w*)*)/,
        Regexp
      )

      # addSbtPlugin("org" % "name" % "version")
      PLUGIN_DEP_REGEX = T.let(
        /addSbtPlugin\(\s*"(?<group>[^"]+)"\s+%\s+"(?<artifact>[^"]+)"\s+%\s+"(?<version>[^"]+)"\s*\)/,
        Regexp
      )

      # addSbtPlugin("org" % "name" % valName)
      # Also handles dotted references like Object.member
      PLUGIN_VAL_REF_REGEX = T.let(
        /addSbtPlugin\(\s*"(?<group>[^"]+)"\s+%\s+"(?<artifact>[^"]+)"\s+%\s+(?<val_name>[a-zA-Z_]\w*(?:\.[a-zA-Z_]\w*)*)\s*\)/,
        Regexp
      )

      # sbt.version=1.x.y in build.properties
      SBT_VERSION_REGEX = T.let(
        /\Asbt\.version\s*=\s*(?<version>.+)\z/,
        Regexp
      )

      # scalaVersion := "2.13.12"  or  ThisBuild / scalaVersion := "2.13.12"
      # Also: scalaVersion in ThisBuild := "2.13.12" (older SBT syntax)
      SCALA_VERSION_REGEX = T.let(
        %r{(?:ThisBuild\s*/\s*)?(?:scalaVersion\s+in\s+ThisBuild|scalaVersion)\s*:=\s*"(?<version>[^"]+)"},
        Regexp
      )

      # scalaVersion := valRef  or  scalaVersion in ThisBuild := V.scala212
      SCALA_VERSION_VAL_REGEX = T.let(
        %r{(?:ThisBuild\s*/\s*)?(?:scalaVersion\s+in\s+ThisBuild|scalaVersion)\s*:=\s*(?<val_name>[a-zA-Z_]\w*(?:\.[a-zA-Z_]\w*)*)},
        Regexp
      )

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        sbt_files.each do |buildfile|
          dependency_set += buildfile_dependencies(buildfile)
        end

        scala_build_files.each do |buildfile|
          dependency_set += buildfile_dependencies(buildfile)
        end

        build_properties_files.each do |properties_file|
          dependency_set += sbt_version_dependency(properties_file)
        end

        sbt_files.each do |buildfile|
          dependency_set += scala_version_dependency(buildfile)
        end

        dependency_set.dependencies
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager,
            language: language
          ),
          T.nilable(Ecosystem)
        )
      end

      private

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          PackageManager.new(sbt_raw_version),
          T.nilable(Dependabot::Sbt::PackageManager)
        )
      end

      sig { returns(T.nilable(Ecosystem::VersionManager)) }
      def language
        @language ||= T.let(
          Language.new(scala_full_version),
          T.nilable(Dependabot::Sbt::Language)
        )
      end

      sig { returns(String) }
      def sbt_raw_version
        build_properties_files.each do |file|
          T.must(file.content).each_line do |line|
            match = line.strip.match(SBT_VERSION_REGEX)
            return T.must(match[:version]).strip if match
          end
        end
        "NOT-AVAILABLE"
      end

      sig { returns(String) }
      def scala_full_version
        sbt_files.each do |file|
          match = prepared_content(file).match(SCALA_VERSION_REGEX)
          return T.must(match[:version]) if match

          val_match = prepared_content(file).match(SCALA_VERSION_VAL_REGEX)
          next unless val_match

          val_name = T.must(val_match[:val_name])
          resolved = property_value_finder.property_value(
            property_name: val_name,
            callsite_buildfile: file
          )
          return resolved if resolved
        end
        "NOT-AVAILABLE"
      end

      sig { params(buildfile: Dependabot::DependencyFile).returns(DependencySet) }
      def buildfile_dependencies(buildfile)
        dependency_set = DependencySet.new

        dependency_set += literal_version_dependencies(buildfile)
        dependency_set += val_ref_dependencies(buildfile)
        dependency_set += plugin_dependencies(buildfile)
        dependency_set += plugin_val_ref_dependencies(buildfile)

        dependency_set
      end

      sig { params(buildfile: Dependabot::DependencyFile).returns(DependencySet) }
      def literal_version_dependencies(buildfile)
        dependency_set = DependencySet.new

        content_without_plugins(buildfile).scan(LIBRARY_DEP_REGEX) do
          captures = T.must(Regexp.last_match).named_captures
          group = T.must(captures.fetch("group"))
          artifact = T.must(captures.fetch("artifact"))
          version = T.must(captures.fetch("version"))
          cross_versioned = captures.fetch("op") == "%%"

          dep_name = build_dependency_name(group, artifact, cross_versioned, buildfile)

          next unless Sbt::Version.correct?(version)

          dependency_set << Dependency.new(
            name: dep_name,
            version: version,
            requirements: [{
              requirement: version,
              file: buildfile.name,
              source: nil,
              groups: [],
              metadata: cross_versioned ? { packaging_type: "cross-versioned" } : nil
            }],
            package_manager: "sbt"
          )
        end

        dependency_set
      end

      sig { params(buildfile: Dependabot::DependencyFile).returns(DependencySet) }
      def val_ref_dependencies(buildfile)
        dependency_set = DependencySet.new

        content_without_plugins(buildfile).scan(VAL_REF_DEP_REGEX) do
          captures = T.must(Regexp.last_match).named_captures
          group = T.must(captures.fetch("group"))
          artifact = T.must(captures.fetch("artifact"))
          val_name = T.must(captures.fetch("val_name"))
          cross_versioned = captures.fetch("op") == "%%"

          property_details = property_value_finder.property_details(
            property_name: val_name,
            callsite_buildfile: buildfile
          )
          next unless property_details

          version = property_details[:value]
          next unless version
          next unless Sbt::Version.correct?(version)

          dep_name = build_dependency_name(group, artifact, cross_versioned, buildfile)

          metadata = T.let(
            { property_name: val_name, property_source: property_details[:file] },
            T::Hash[Symbol, T.untyped]
          )
          metadata[:packaging_type] = "cross-versioned" if cross_versioned

          dependency_set << Dependency.new(
            name: dep_name,
            version: version,
            requirements: [{
              requirement: version,
              file: buildfile.name,
              source: nil,
              groups: [],
              metadata: metadata
            }],
            package_manager: "sbt"
          )
        end

        dependency_set
      end

      sig { params(buildfile: Dependabot::DependencyFile).returns(DependencySet) }
      def plugin_dependencies(buildfile)
        dependency_set = DependencySet.new

        prepared_content(buildfile).scan(PLUGIN_DEP_REGEX) do
          captures = T.must(Regexp.last_match).named_captures
          group = T.must(captures.fetch("group"))
          artifact = T.must(captures.fetch("artifact"))
          version = T.must(captures.fetch("version"))

          next unless Sbt::Version.correct?(version)

          dependency_set << Dependency.new(
            name: "#{group}:#{artifact}",
            version: version,
            requirements: [{
              requirement: version,
              file: buildfile.name,
              source: nil,
              groups: ["plugins"],
              metadata: nil
            }],
            package_manager: "sbt"
          )
        end

        dependency_set
      end

      sig { params(buildfile: Dependabot::DependencyFile).returns(DependencySet) }
      def plugin_val_ref_dependencies(buildfile)
        dependency_set = DependencySet.new

        prepared_content(buildfile).scan(PLUGIN_VAL_REF_REGEX) do
          captures = T.must(Regexp.last_match).named_captures
          group = T.must(captures.fetch("group"))
          artifact = T.must(captures.fetch("artifact"))
          val_name = T.must(captures.fetch("val_name"))

          property_details = property_value_finder.property_details(
            property_name: val_name,
            callsite_buildfile: buildfile
          )
          next unless property_details

          version = property_details[:value]
          next unless version
          next unless Sbt::Version.correct?(version)

          dependency_set << Dependency.new(
            name: "#{group}:#{artifact}",
            version: version,
            requirements: [{
              requirement: version,
              file: buildfile.name,
              source: nil,
              groups: ["plugins"],
              metadata: { property_name: val_name, property_source: property_details[:file] }
            }],
            package_manager: "sbt"
          )
        end

        dependency_set
      end

      sig { params(properties_file: Dependabot::DependencyFile).returns(DependencySet) }
      def sbt_version_dependency(properties_file)
        dependency_set = DependencySet.new

        T.must(properties_file.content).each_line do |line|
          line = line.strip
          next if line.empty? || line.start_with?("#", "!")

          match = line.match(SBT_VERSION_REGEX)
          next unless match

          version = T.must(match[:version]).strip
          next unless Sbt::Version.correct?(version)

          dependency_set << Dependency.new(
            name: "org.scala-sbt:sbt",
            version: version,
            requirements: [{
              requirement: version,
              file: properties_file.name,
              source: nil,
              groups: [],
              metadata: { property_source: "build.properties" }
            }],
            package_manager: "sbt"
          )

          break
        end

        dependency_set
      end

      sig { params(buildfile: Dependabot::DependencyFile).returns(DependencySet) }
      def scala_version_dependency(buildfile)
        dependency_set = DependencySet.new

        match = prepared_content(buildfile).match(SCALA_VERSION_REGEX)
        return dependency_set unless match

        version = T.must(match[:version])
        return dependency_set unless Sbt::Version.correct?(version)

        # Scala 3 uses scala3-library, Scala 2 uses scala-library
        dep_name = version.start_with?("3") ? "org.scala-lang:scala3-library_3" : "org.scala-lang:scala-library"

        dependency_set << Dependency.new(
          name: dep_name,
          version: version,
          requirements: [{
            requirement: version,
            file: buildfile.name,
            source: nil,
            groups: [],
            metadata: { property_source: "scalaVersion" }
          }],
          package_manager: "sbt"
        )

        dependency_set
      end

      sig do
        params(
          group: String,
          artifact: String,
          cross_versioned: T::Boolean,
          buildfile: Dependabot::DependencyFile
        ).returns(String)
      end
      def build_dependency_name(group, artifact, cross_versioned, buildfile)
        if cross_versioned
          scala_major = scala_major_version_for(buildfile)
          "#{group}:#{artifact}_#{scala_major}"
        else
          "#{group}:#{artifact}"
        end
      end

      sig { params(buildfile: Dependabot::DependencyFile).returns(String) }
      def scala_major_version_for(buildfile)
        # Check the buildfile itself first, then fall back to root build.sbt
        files_to_check = [buildfile]
        root = sbt_files.find { |f| f.name == "build.sbt" }
        files_to_check << root if root && root != buildfile

        files_to_check.each do |file|
          # Try literal scalaVersion first
          match = prepared_content(file).match(SCALA_VERSION_REGEX)
          if match
            full_version = T.must(match[:version])
            return extract_scala_major(full_version)
          end

          # Try val-reference scalaVersion (e.g. scalaVersion := myVal or := V.scala212)
          val_match = prepared_content(file).match(SCALA_VERSION_VAL_REGEX)
          next unless val_match

          val_name = T.must(val_match[:val_name])
          resolved = property_value_finder.property_value(
            property_name: val_name,
            callsite_buildfile: file
          )
          return extract_scala_major(resolved) if resolved
        end

        # Default to 2.13 if scalaVersion is not declared
        "2.13"
      end

      sig { params(full_version: String).returns(String) }
      def extract_scala_major(full_version)
        parts = full_version.split(".")
        parts[0] == "3" ? "3" : "#{parts[0]}.#{parts[1]}"
      end

      sig { params(buildfile: Dependabot::DependencyFile).returns(String) }
      def prepared_content(buildfile)
        T.must(buildfile.content)
         .gsub(%r{(?<=^|\s)//.*$}, "\n")
         .gsub(%r{(?<=^|\s)/\*.*?\*/}m, "")
      end

      # Returns prepared content with addSbtPlugin(...) calls removed so that
      # LIBRARY_DEP_REGEX and VAL_REF_DEP_REGEX do not duplicate plugin matches.
      sig { params(buildfile: Dependabot::DependencyFile).returns(String) }
      def content_without_plugins(buildfile)
        prepared_content(buildfile).gsub(/addSbtPlugin\([^)]*\)/, "")
      end

      sig { returns(PropertyValueFinder) }
      def property_value_finder
        @property_value_finder ||= T.let(
          PropertyValueFinder.new(dependency_files: dependency_files),
          T.nilable(PropertyValueFinder)
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def sbt_files
        @sbt_files ||= T.let(
          dependency_files.select { |f| f.name.end_with?(".sbt") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def build_properties_files
        @build_properties_files ||= T.let(
          dependency_files.select { |f| f.name.end_with?("build.properties") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def scala_build_files
        @scala_build_files ||= T.let(
          dependency_files.select { |f| f.name.end_with?(".scala") && f.name.start_with?("project/") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { override.void }
      def check_required_files
        return if dependency_files.any? { |f| f.name.end_with?(BUILD_SBT_FILENAME) }

        raise "No build.sbt!"
      end
    end
  end
end

Dependabot::FileParsers.register("sbt", Dependabot::Sbt::FileParser)
