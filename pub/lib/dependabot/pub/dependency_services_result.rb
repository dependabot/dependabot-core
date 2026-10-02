# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/pub/json_value_parser"
require "dependabot/shared_helpers"

module Dependabot
  module Pub
    module DependencyServicesResult
      extend T::Sig

      class ListedDependency < T::ImmutableStruct
        const :name, String
        const :version, String
        const :kind, String
        const :constraint, T.nilable(String)
        const :source, T.nilable(JsonValueParser::ObjectHash)
      end

      class DependencyUpdate < T::ImmutableStruct
        const :name, String
        const :version, T.nilable(String)
        const :kind, String
        const :previous_version, T.nilable(String)
        const :previous_constraint, T.nilable(String)
        const :constraint_bumped, T.nilable(String)
        const :constraint_bumped_if_needed, T.nilable(String)
        const :constraint_widened, T.nilable(String)
      end

      class ReportEntry < T::ImmutableStruct
        const :name, String
        const :version, String
        const :latest, T.nilable(String)
        const :compatible, T::Array[DependencyUpdate]
        const :single_breaking, T::Array[DependencyUpdate]
        const :multi_breaking, T::Array[DependencyUpdate]
        const :smallest_update, T.nilable(T::Array[DependencyUpdate])
      end

      class Report < T::ImmutableStruct
        const :dependencies, T::Array[ReportEntry]
        const :cache_content, String
      end

      sig { params(content: String).returns(T::Array[ListedDependency]) }
      def self.list_from_json(content)
        context = "dependency_services list"
        root = JsonValueParser.object(JsonValueParser.parse(content, context), context)
        JsonValueParser.array(root["dependencies"], "#{context}.dependencies").each_with_index.map do |value, index|
          entry_context = "#{context}.dependencies[#{index}]"
          fields = JsonValueParser.object(value, entry_context)
          ListedDependency.new(
            name: JsonValueParser.string(fields["name"], "#{entry_context}.name"),
            version: JsonValueParser.string(fields["version"], "#{entry_context}.version"),
            kind: JsonValueParser.string(fields["kind"], "#{entry_context}.kind"),
            constraint: JsonValueParser.optional_string(fields["constraint"], "#{entry_context}.constraint"),
            source: JsonValueParser.optional_object(fields["source"], "#{entry_context}.source")
          )
        end
      rescue JsonValueParser::InvalidValue => e
        invalid_result("dependency_services list", e.message)
      end

      sig { params(content: String).returns(Report) }
      def self.report_from_json(content)
        context = "dependency_services report"
        root = JsonValueParser.object(JsonValueParser.parse(content, context), context)
        build_report(root["dependencies"], "#{context}.dependencies")
      rescue JsonValueParser::InvalidValue => e
        invalid_result("dependency_services report", e.message)
      end

      sig { params(content: String).returns(Report) }
      def self.report_from_cache(content)
        context = "dependency_services report cache"
        build_report(JsonValueParser.parse(content, context), context)
      rescue JsonValueParser::InvalidValue => e
        invalid_result("dependency_services report cache", e.message)
      end

      sig { params(reports: T::Array[ReportEntry], name: String).returns(ReportEntry) }
      def self.find_report(reports, name)
        report = reports.find { |entry| entry.name == name }
        return report if report

        invalid_result(
          "dependency_services report",
          "dependency_services report does not include the requested dependency"
        )
      end

      sig { params(context: String, message: String).returns(T.noreturn) }
      def self.invalid_result(context, message)
        raise SharedHelpers::HelperSubprocessFailed.new(
          message: message,
          error_class: "TypeError",
          error_context: { function: context }
        ),
              cause: nil
      end

      sig { params(value: Object, context: String).returns(Report) }
      def self.build_report(value, context)
        raw_entries = JsonValueParser.array(value, context)
        entries = raw_entries.each_with_index.map do |entry, index|
          report_entry(entry, "#{context}[#{index}]")
        end
        Report.new(dependencies: entries, cache_content: JSON.generate(raw_entries))
      end
      private_class_method :build_report

      sig { params(value: Object, context: String).returns(ReportEntry) }
      def self.report_entry(value, context)
        fields = JsonValueParser.object(value, context)
        ReportEntry.new(
          name: JsonValueParser.string(fields["name"], "#{context}.name"),
          version: JsonValueParser.string(fields["version"], "#{context}.version"),
          latest: JsonValueParser.optional_string(fields["latest"], "#{context}.latest"),
          compatible: updates(fields["compatible"], "#{context}.compatible"),
          single_breaking: updates(fields["singleBreaking"], "#{context}.singleBreaking"),
          multi_breaking: updates(fields["multiBreaking"], "#{context}.multiBreaking"),
          smallest_update: if fields.key?("smallestUpdate")
                             updates(
                               fields["smallestUpdate"],
                               "#{context}.smallestUpdate"
                             )
                           end
        )
      end
      private_class_method :report_entry

      sig { params(value: Object, context: String).returns(T::Array[DependencyUpdate]) }
      def self.updates(value, context)
        JsonValueParser.array(value, context).each_with_index.map do |entry, index|
          entry_context = "#{context}[#{index}]"
          fields = JsonValueParser.object(entry, entry_context)
          DependencyUpdate.new(
            name: JsonValueParser.string(fields["name"], "#{entry_context}.name"),
            version: JsonValueParser.optional_string(fields["version"], "#{entry_context}.version"),
            kind: JsonValueParser.string(fields["kind"], "#{entry_context}.kind"),
            previous_version: JsonValueParser.optional_string(
              fields["previousVersion"],
              "#{entry_context}.previousVersion"
            ),
            previous_constraint: JsonValueParser.optional_string(
              fields["previousConstraint"], "#{entry_context}.previousConstraint"
            ),
            constraint_bumped: JsonValueParser.optional_string(
              fields["constraintBumped"],
              "#{entry_context}.constraintBumped"
            ),
            constraint_bumped_if_needed: JsonValueParser.optional_string(
              fields["constraintBumpedIfNeeded"], "#{entry_context}.constraintBumpedIfNeeded"
            ),
            constraint_widened: JsonValueParser.optional_string(
              fields["constraintWidened"],
              "#{entry_context}.constraintWidened"
            )
          )
        end
      end
      private_class_method :updates
    end
  end
end
