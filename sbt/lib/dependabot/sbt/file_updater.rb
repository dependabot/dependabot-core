# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/sbt/file_parser"

module Dependabot
  module Sbt
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/property_value_updater"

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = T.let(dependency_files.dup, T::Array[Dependabot::DependencyFile])

        dependencies.each do |dependency|
          updated_files = update_files_for_dependency(
            original_files: updated_files,
            dependency: dependency
          )
        end

        updated_files.reject! { |f| dependency_files.include?(f) }

        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      sig { override.void }
      def check_required_files
        raise "No build.sbt!" unless get_original_file("build.sbt")
      end

      sig do
        params(
          original_files: T::Array[Dependabot::DependencyFile],
          dependency: Dependabot::Dependency
        ).returns(T::Array[Dependabot::DependencyFile])
      end
      def update_files_for_dependency(original_files:, dependency:)
        files = original_files.dup

        reqs = dependency.requirements.zip(dependency.previous_requirements.to_a)
                         .reject { |new_req, old_req| new_req == old_req }

        reqs.each do |new_req, old_req|
          raise "Bad req match" unless new_req[:file] == T.must(old_req)[:file]
          next if new_req[:requirement] == T.must(old_req)[:requirement]

          if new_req.dig(:metadata, :property_name)
            files = update_files_for_property_change(files, T.must(old_req), new_req)
          elsif T.let(new_req[:file], String).end_with?("build.properties")
            files = update_build_properties(files, T.must(old_req), new_req)
          elsif scala_version_requirement?(new_req)
            file = T.must(files.find { |f| f.name == new_req[:file] })
            files[T.must(files.index(file))] = update_scala_version(file, T.must(old_req), new_req)
          else
            file = T.must(files.find { |f| f.name == new_req[:file] })
            files[T.must(files.index(file))] = update_version_in_buildfile(dependency, file, T.must(old_req), new_req)
          end
        end

        files
      end

      sig do
        params(
          files: T::Array[Dependabot::DependencyFile],
          old_req: T::Hash[Symbol, T.untyped],
          new_req: T::Hash[Symbol, T.untyped]
        ).returns(T::Array[Dependabot::DependencyFile])
      end
      def update_files_for_property_change(files, old_req, new_req)
        property_name = T.let(new_req.dig(:metadata, :property_name), String)
        callsite = T.must(files.find { |f| f.name == new_req[:file] })

        PropertyValueUpdater.new(dependency_files: files)
                            .update_files_for_property_change(
                              property_name: property_name,
                              callsite_buildfile: callsite,
                              previous_value: T.let(old_req.fetch(:requirement), String),
                              updated_value: T.let(new_req.fetch(:requirement), String)
                            )
      end

      sig do
        params(
          files: T::Array[Dependabot::DependencyFile],
          old_req: T::Hash[Symbol, T.untyped],
          new_req: T::Hash[Symbol, T.untyped]
        ).returns(T::Array[Dependabot::DependencyFile])
      end
      def update_build_properties(files, old_req, new_req)
        file = T.must(files.find { |f| f.name == new_req[:file] })
        old_version = T.let(old_req.fetch(:requirement), String)
        new_version = T.let(new_req.fetch(:requirement), String)

        updated_content = T.must(file.content).sub(
          /(sbt\.version\s*=\s*)#{Regexp.quote(old_version)}/,
          "\\1#{new_version}"
        )

        raise "Expected content to change!" if updated_content == file.content

        updated_files = files.dup
        updated_files[T.must(files.index(file))] =
          updated_file(file: file, content: updated_content)
        updated_files
      end

      sig do
        params(
          file: Dependabot::DependencyFile,
          old_req: T::Hash[Symbol, T.untyped],
          new_req: T::Hash[Symbol, T.untyped]
        ).returns(Dependabot::DependencyFile)
      end
      def update_scala_version(file, old_req, new_req)
        old_version = T.let(old_req.fetch(:requirement), String)
        new_version = T.let(new_req.fetch(:requirement), String)

        updated_content = T.must(file.content).sub(
          %r{((?:ThisBuild\s*/\s*)?(?:scalaVersion\s+in\s+ThisBuild|scalaVersion)\s*:=\s*")#{Regexp.quote(old_version)}(")},
          "\\1#{new_version}\\2"
        )

        raise "Expected content to change!" if updated_content == file.content

        updated_file(file: file, content: updated_content)
      end

      sig do
        params(
          dependency: Dependabot::Dependency,
          buildfile: Dependabot::DependencyFile,
          previous_req: T::Hash[Symbol, T.untyped],
          requirement: T::Hash[Symbol, T.untyped]
        ).returns(Dependabot::DependencyFile)
      end
      def update_version_in_buildfile(dependency, buildfile, previous_req, requirement)
        updated_content = T.must(buildfile.content.dup)

        original_declarations = original_buildfile_declarations(dependency, previous_req)
        original_declarations.each do |old_dec|
          updated_content = updated_content.gsub(old_dec) do
            updated_buildfile_declaration(old_dec, previous_req, requirement)
          end
        end

        raise "Expected content to change!" if updated_content == buildfile.content

        updated_file(file: buildfile, content: updated_content)
      end

      sig do
        params(
          dependency: Dependabot::Dependency,
          requirement: T::Hash[Symbol, T.untyped]
        ).returns(T::Array[String])
      end
      def original_buildfile_declarations(dependency, requirement)
        buildfile = T.must(dependency_files.find { |f| f.name == T.let(requirement.fetch(:file), String) })
        group, artifact = dependency_group_and_artifact(dependency)

        T.must(buildfile.content).lines.select do |line|
          next false unless line.include?(group)
          next false unless line.include?(artifact)

          line.include?(T.let(requirement.fetch(:requirement), String))
        end
      end

      sig { params(dependency: Dependabot::Dependency).returns([String, String]) }
      def dependency_group_and_artifact(dependency)
        parts = dependency.name.split(":")
        group = T.must(parts.first)
        artifact = T.must(parts.last)

        # Strip Scala version suffix for cross-versioned deps (e.g. cats-core_2.13 → cats-core)
        artifact = artifact.sub(/_\d+(\.\d+)?$/, "")

        [group, artifact]
      end

      sig do
        params(
          old_declaration: String,
          previous_req: T::Hash[Symbol, T.untyped],
          requirement: T::Hash[Symbol, T.untyped]
        ).returns(String)
      end
      def updated_buildfile_declaration(old_declaration, previous_req, requirement)
        original_req_string = T.let(previous_req.fetch(:requirement), String)
        new_req_string = T.let(requirement.fetch(:requirement), String)

        old_declaration.gsub(
          /"#{Regexp.quote(original_req_string)}"/,
          "\"#{new_req_string}\""
        )
      end

      sig { params(req: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
      def scala_version_requirement?(req)
        req.dig(:metadata, :property_source) == "scalaVersion"
      end
    end
  end
end

Dependabot::FileUpdaters.register("sbt", Dependabot::Sbt::FileUpdater)
