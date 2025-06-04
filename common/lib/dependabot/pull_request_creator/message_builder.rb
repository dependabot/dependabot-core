# typed: strict
# frozen_string_literal: true

require "time"
require "pathname"
require "sorbet-runtime"

require "dependabot/clients/github_with_retries"
require "dependabot/clients/gitlab_with_retries"
require "dependabot/dependency_group"
require "dependabot/logger"
require "dependabot/metadata_finders"
require "dependabot/pull_request_creator"
require "dependabot/pull_request_creator/message"
require "dependabot/notices"

# rubocop:disable Metrics/ClassLength
module Dependabot
  class PullRequestCreator
    # MessageBuilder builds PR message for a dependency update
    class MessageBuilder
      extend T::Sig

      require_relative "message_builder/metadata_presenter"
      require_relative "message_builder/issue_linker"
      require_relative "message_builder/link_and_mention_sanitizer"
      require_relative "pr_name_prefixer"

      sig { returns(Dependabot::Source) }
      attr_reader :source

      sig { returns(T::Array[Dependabot::Dependency]) }
      attr_reader :dependencies

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      attr_reader :files

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { returns(T.nilable(String)) }
      attr_reader :pr_message_header

      sig { returns(T.nilable(String)) }
      attr_reader :pr_message_footer

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      attr_reader :commit_message_options

      sig { returns(T::Hash[String, T.untyped]) }
      attr_reader :vulnerabilities_fixed

      sig { returns(T.nilable(String)) }
      attr_reader :github_redirection_service

      sig { returns(T.nilable(Dependabot::DependencyGroup)) }
      attr_reader :dependency_group

      sig { returns(T.nilable(Integer)) }
      attr_reader :pr_message_max_length

      sig { returns(T.nilable(Encoding)) }
      attr_reader :pr_message_encoding

      sig { returns(T::Array[T::Hash[String, String]]) }
      attr_reader :ignore_conditions

      sig { returns(T.nilable(T::Array[Dependabot::Notice])) }
      attr_reader :notices

      TRUNCATED_MSG = "...\n\n_Description has been truncated_"

      sig do
        params(
          source: Dependabot::Source,
          dependencies: T::Array[Dependabot::Dependency],
          files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential],
          pr_message_header: T.nilable(String),
          pr_message_footer: T.nilable(String),
          commit_message_options: T.nilable(T::Hash[Symbol, T.untyped]),
          vulnerabilities_fixed: T::Hash[String, T.untyped],
          github_redirection_service: T.nilable(String),
          dependency_group: T.nilable(Dependabot::DependencyGroup),
          pr_message_max_length: T.nilable(Integer),
          pr_message_encoding: T.nilable(Encoding),
          ignore_conditions: T::Array[T::Hash[String, String]],
          notices: T.nilable(T::Array[Dependabot::Notice])
        )
          .void
      end
      def initialize(source:, dependencies:, files:, credentials:,
                     pr_message_header: nil, pr_message_footer: nil,
                     commit_message_options: {}, vulnerabilities_fixed: {},
                     github_redirection_service: DEFAULT_GITHUB_REDIRECTION_SERVICE,
                     dependency_group: nil, pr_message_max_length: nil, pr_message_encoding: nil,
                     ignore_conditions: [], notices: nil)
        @dependencies               = dependencies
        @files                      = files
        @source                     = source
        @credentials                = credentials
        @pr_message_header          = pr_message_header
        @pr_message_footer          = pr_message_footer
        @commit_message_options     = commit_message_options
        @vulnerabilities_fixed      = vulnerabilities_fixed
        @github_redirection_service = github_redirection_service
        @dependency_group           = dependency_group
        @pr_message_max_length      = pr_message_max_length
        @pr_message_encoding        = pr_message_encoding
        @ignore_conditions          = ignore_conditions
        @notices                    = notices
      end

      sig { params(pr_message_max_length: Integer).returns(Integer) }
      attr_writer :pr_message_max_length

      sig { params(pr_message_encoding: Encoding).returns(Encoding) }
      attr_writer :pr_message_encoding

      sig { returns(String) }
      def pr_name
        name = dependency_group ? group_pr_name : solo_pr_name
        name[0] = T.must(name[0]).capitalize if pr_name_prefixer.capitalize_first_word?
        "#{pr_name_prefix}#{name}"
      end

      sig { returns(String) }
      def pr_message
        msg = "#{pr_notices}" \
              "#{suffixed_pr_message_header}" \
              "#{commit_message_intro}" \
              "#{metadata_cascades}" \
              "#{ignore_conditions_table}" \
              "#{prefixed_pr_message_footer}"

        truncate_pr_message(msg)
      rescue StandardError => e
        suppress_error("PR message", e)
        suffixed_pr_message_header + prefixed_pr_message_footer
      end

      sig { returns(T.nilable(String)) }
      def pr_notices
        notices = @notices || []
        unique_messages = notices.filter_map do |notice|
          Dependabot::Notice.markdown_from_description(notice) if notice.show_in_pr
        end.uniq

        message = unique_messages.join("\n\n")
        message.empty? ? nil : message
      end

      # Truncate PR message as determined by the pr_message_max_length and pr_message_encoding instance variables
      # The encoding is used when calculating length, all messages are returned as ruby UTF_8 encoded string
      sig { params(msg: String).returns(String) }
      def truncate_pr_message(msg)
        return msg if pr_message_max_length.nil?

        msg = msg.dup
        msg = msg.force_encoding(T.must(pr_message_encoding)) unless pr_message_encoding.nil?

        if msg.length > T.must(pr_message_max_length)
          tr_msg = if pr_message_encoding.nil?
                     TRUNCATED_MSG
                   else
                     (+TRUNCATED_MSG).dup.force_encoding(T.must(pr_message_encoding))
                   end
          trunc_length = T.must(pr_message_max_length) - tr_msg.length
          msg = (T.must(msg[0..trunc_length]) + tr_msg)
        end
        # if we used a custom encoding for calculating length, then we need to force back to UTF-8
        msg = msg.encode("utf-8", "binary", invalid: :replace, undef: :replace) unless pr_message_encoding.nil?
        msg
      end

      sig { returns(String) }
      def commit_message
        message = commit_subject + "\n\n"
        message += commit_message_intro
        message += metadata_links
        message += "\n\n" + T.must(message_trailers) if message_trailers
        message
      rescue StandardError => e
        suppress_error("commit message", e)
        message = commit_subject
        message += "\n\n" + T.must(message_trailers) if message_trailers
        message
      end

      sig { returns(Dependabot::PullRequestCreator::Message) }
      def message
        Dependabot::PullRequestCreator::Message.new(
          pr_name: pr_name,
          pr_message: pr_message,
          commit_message: commit_message
        )
      end

      private

      sig { returns(String) }
      def solo_pr_name
        name = library? ? library_pr_name : application_pr_name
        "#{name}#{pr_name_directory}"
      end

      sig { returns(String) }
      def library_pr_name
        "update " +
          if dependencies.count == 1
            "#{T.must(dependencies.first).display_name} requirement " \
              "#{from_version_msg(old_library_requirement(T.must(dependencies.first)))}" \
              "to #{new_library_requirement(T.must(dependencies.first))}"
          else
            names = dependencies.map(&:name).uniq
            if names.count == 1
              "requirements for #{names.first}"
            else
              "requirements for #{T.must(names[0..-2]).join(', ')} and #{names[-1]}"
            end
          end
      end

      # rubocop:disable Metrics/AbcSize
      sig { returns(String) }
      def application_pr_name
        "bump " +
          if dependencies.count == 1
            dependency = dependencies.first
            "#{T.must(dependency).display_name} " \
              "#{from_version_msg(T.must(dependency).humanized_previous_version)}" \
              "to #{T.must(dependency).humanized_version}"
          elsif updating_a_property?
            dependency = dependencies.first
            "#{property_name} " \
              "#{from_version_msg(T.must(dependency).humanized_previous_version)}" \
              "to #{T.must(dependency).humanized_version}"
          elsif updating_a_dependency_set?
            dependency = dependencies.first
            "#{dependency_set.fetch(:group)} dependency set " \
              "#{from_version_msg(T.must(dependency).humanized_previous_version)}" \
              "to #{T.must(dependency).humanized_version}"
          else
            names = dependencies.map(&:name).uniq
            if names.count == 1
              T.must(names.first)
            else
              "#{T.must(names[0..-2]).join(', ')} and #{names[-1]}"
            end
          end
      end
      # rubocop:enable Metrics/AbcSize

      sig { returns(String) }
      def group_pr_name
        if source.directories
          grouped_directory_name
        else
          grouped_name
        end
      end

      sig { returns(String) }
      def grouped_name
        updates = dependencies.map(&:name).uniq.count
        if dependencies.count == 1
          "#{solo_pr_name} in the #{T.must(dependency_group).name} group"
        else
          "bump the #{T.must(dependency_group).name} group#{pr_name_directory} " \
            "with #{updates} update#{'s' if updates > 1}"
        end
      end

      sig { returns(String) }
      def grouped_directory_name
        updates = dependencies.map(&:name).uniq.count

        directories_from_dependencies = dependencies.to_set { |dep| dep.metadata[:directory] }

        directories_with_updates = source.directories&.filter do |directory|
          directories_from_dependencies.include?(directory)
        end

        if dependencies.count == 1
          "#{solo_pr_name} in the #{T.must(dependency_group).name} group across " \
            "#{T.must(directories_with_updates).count} directory"
        else
          "bump the #{T.must(dependency_group).name} group across #{T.must(directories_with_updates).count} " \
            "#{T.must(directories_with_updates).count > 1 ? 'directories' : 'directory'} " \
            "with #{updates} update#{'s' if updates > 1}"
        end
      end

      sig { returns(String) }
      def pr_name_prefix
        pr_name_prefixer.pr_name_prefix
      rescue StandardError => e
        suppress_error("PR name", e)
        ""
      end

      sig { returns(String) }
      def pr_name_directory
        return "" if T.must(files.first).directory == "/"

        " in #{T.must(files.first).directory}"
      end

      sig { returns(String) }
      def commit_subject
        subject = pr_name.gsub("⬆️", ":arrow_up:").gsub("🔒", ":lock:")
        return subject unless subject.length > 72

        subject = subject.gsub(/ from [^\s]*? to [^\s]*/, "")
        return subject unless subject.length > 72

        T.must(subject.split(" in ").first)
      end

      sig { returns(String) }
      def commit_message_intro
        return requirement_commit_message_intro if library?

        version_commit_message_intro
      end

      sig { returns(String) }
      def prefixed_pr_message_footer
        return "" unless pr_message_footer

        "\n\n#{pr_message_footer}"
      end

      sig { returns(String) }
      def suffixed_pr_message_header
        return "" unless pr_message_header

        return "#{pr_message_header}\n\n" if notices

        "#{pr_message_header}\n\n"
      end

      sig { returns(T.nilable(String)) }
      def message_trailers
        return unless signoff_trailers || custom_trailers

        [signoff_trailers, custom_trailers].compact.join("\n")
      end

      sig { returns(T.nilable(String)) }
      def custom_trailers
        trailers = commit_message_options&.dig(:trailers)
        return if trailers.nil?
        raise("Commit trailers must be a Hash object") unless trailers.is_a?(Hash)

        trailers.compact.map { |k, v| "#{k}: #{v}" }.join("\n")
      end

      sig { returns(T.nilable(String)) }
      def signoff_trailers
        return unless on_behalf_of_message || signoff_message

        [on_behalf_of_message, signoff_message].compact.join("\n")
      end

      sig { returns(T.nilable(String)) }
      def signoff_message
        signoff_details = commit_message_options&.dig(:signoff_details)
        return unless signoff_details.is_a?(Hash)
        return unless signoff_details[:name] && signoff_details[:email]

        "Signed-off-by: #{signoff_details[:name]} <#{signoff_details[:email]}>"
      end

      sig { returns(T.nilable(String)) }
      def on_behalf_of_message
        signoff_details = commit_message_options&.dig(:signoff_details)
        return unless signoff_details.is_a?(Hash)
        return unless signoff_details[:org_name] && signoff_details[:org_email]

        "On-behalf-of: @#{signoff_details[:org_name]} " \
          "<#{signoff_details[:org_email]}>"
      end

      sig { returns(String) }
      def requirement_commit_message_intro
        msg = "Updates the requirements on "

        msg +=
          if dependencies.count == 1
            "#{dependency_links.first} "
          else
            "#{T.must(dependency_links[0..-2]).join(', ')} and #{dependency_links[-1]} "
          end

        msg + "to permit the latest version."
      end

      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/AbcSize
      sig { returns(String) }
      def version_commit_message_intro
        return multi_directory_group_intro if dependency_group && source.directories

        return group_intro if dependency_group

        return multidependency_property_intro if dependencies.count > 1 && updating_a_property?

        return dependency_set_intro if dependencies.count > 1 && updating_a_dependency_set?

        return transitive_removed_dependency_intro if dependencies.count > 1 && removing_a_transitive_dependency?

        return transitive_multidependency_intro if dependencies.count > 1 &&
                                                   updating_top_level_and_transitive_dependencies?

        return multidependency_intro if dependencies.count > 1

        dependency = dependencies.first
        msg = "Bumps #{dependency_links.first} " \
              "#{from_version_msg(T.must(dependency).humanized_previous_version)}" \
              "to #{T.must(dependency).humanized_version}."

        if switching_from_ref_to_release?(T.must(dependency))
          msg += " This release includes the previously tagged commit."
        end

        if vulnerabilities_fixed[T.must(dependency).name]&.one?
          msg += " **This update includes a security fix.**"
        elsif vulnerabilities_fixed[T.must(dependency).name]&.any?
          msg += " **This update includes security fixes.**"
        end

        msg
      end
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/AbcSize

      sig { returns(String) }
      def multidependency_property_intro
        dependency = dependencies.first

        "Bumps `#{property_name}` " \
          "#{from_version_msg(T.must(dependency).humanized_previous_version)}" \
          "to #{T.must(dependency).humanized_version}."
      end

      sig { returns(String) }
      def dependency_set_intro
        dependency = dependencies.first

        "Bumps `#{dependency_set.fetch(:group)}` " \
          "dependency set #{from_version_msg(T.must(dependency).humanized_previous_version)}" \
          "to #{T.must(dependency).humanized_version}."
      end

      sig { returns(String) }
      def multidependency_intro
        "Bumps #{T.must(dependency_links[0..-2]).join(', ')} " \
          "and #{dependency_links[-1]}. These " \
          "dependencies needed to be updated together."
      end

      sig { returns(String) }
      def transitive_multidependency_intro
        dependency = dependencies.first

        msg = "Bumps #{dependency_links[0]} to #{T.must(dependency).humanized_version}"

        msg += if dependencies.count > 2
                 " and updates ancestor dependencies #{T.must(dependency_links[0..-2]).join(', ')} " \
                   "and #{dependency_links[-1]}. "
               else
                 " and updates ancestor dependency #{dependency_links[1]}. "
               end

        msg += "These dependencies need to be updated together.\n"

        msg
      end

      sig { returns(String) }
      def transitive_removed_dependency_intro
        msg = "Removes #{dependency_links[0]}. It's no longer used after updating"

        msg += if dependencies.count > 2
                 " ancestor dependencies #{T.must(dependency_links[0..-2]).join(', ')} " \
                   "and #{dependency_links[-1]}. "
               else
                 " ancestor dependency #{dependency_links[1]}. "
               end

        msg += "These dependencies need to be updated together.\n"

        msg
      end

      # rubocop:disable Metrics/AbcSize
      sig { returns(String) }
      def multi_directory_group_intro
        msg = ""

        T.must(source.directories).each do |directory|
          dependencies_in_directory = dependencies.select { |dep| dep.metadata[:directory] == directory }
          next unless dependencies_in_directory.any?

          update_count = dependencies_in_directory.map(&:name).uniq.count

          msg += "Bumps the #{T.must(dependency_group).name} group " \
                 "with #{update_count} update#{update_count > 1 ? 's' : ''} in the #{directory} directory:"

          msg += if update_count >= 5
                   header = %w(Package From To)
                   rows = dependencies_in_directory.map do |dep|
                     [
                       dependency_link(dep),
                       "`#{dep.humanized_previous_version}`",
                       "`#{dep.humanized_version}`"
                     ]
                   end
                   "\n\n#{table([header] + rows)}\n"
                 elsif update_count > 1
                   dependency_links_in_directory = dependency_links_for_directory(directory)
                   " #{T.must(T.must(dependency_links_in_directory)[0..-2]).join(', ')}" \
                     " and #{T.must(dependency_links_in_directory)[-1]}."
                 else
                   dependency_links_in_directory = dependency_links_for_directory(directory)
                   " #{T.must(dependency_links_in_directory).first}."
                 end

          msg += "\n"
        end

        msg
      end
      # rubocop:enable Metrics/AbcSize

      sig { returns(String) }
      def group_intro
        # Ensure dependencies are unique by name, from and to versions
        unique_dependencies = dependencies.uniq { |dep| [dep.name, dep.previous_version, dep.version] }
        update_count = unique_dependencies.count

        msg = "Bumps the #{T.must(dependency_group).name} group#{pr_name_directory} " \
              "with #{update_count} update#{update_count > 1 ? 's' : ''}:"

        msg += if update_count >= 5
                 header = %w(Package From To)
                 rows = unique_dependencies.map do |dep|
                   [
                     dependency_link(dep),
                     "`#{dep.humanized_previous_version}`",
                     "`#{dep.humanized_version}`"
                   ]
                 end
                 "\n\n#{table([header] + rows)}"
               elsif update_count > 1
                 " #{T.must(dependency_links[0..-2]).join(', ')} and #{dependency_links[-1]}."
               else
                 " #{dependency_links.first}."
               end

        msg += "\n"

        msg
      end

      sig { params(previous_version: T.nilable(String)).returns(String) }
      def from_version_msg(previous_version)
        return "" unless previous_version

        "from #{previous_version} "
      end

      sig { returns(T::Boolean) }
      def updating_a_property?
        T.must(dependencies.first)
         .requirements
         .any? { |r| r.dig(:metadata, :property_name) }
      end

      sig { returns(T::Boolean) }
      def updating_a_dependency_set?
        T.must(dependencies.first)
         .requirements
         .any? { |r| r.dig(:metadata, :dependency_set) }
      end

      sig { returns(T::Boolean) }
      def removing_a_transitive_dependency?
        dependencies.any?(&:removed?)
      end

      sig { returns(T::Boolean) }
      def updating_top_level_and_transitive_dependencies?
        dependencies.any?(&:top_level?) &&
          dependencies.any? { |dep| !dep.top_level? }
      end

      sig { returns(String) }
      def property_name
        @property_name ||=
          T.let(
            dependencies.first
              &.requirements
              &.find { |r| r.dig(:metadata, :property_name) }
              &.dig(:metadata, :property_name),
            T.nilable(String)
          )

        raise "No property name!" unless @property_name

        @property_name
      end

      sig { returns(T::Hash[Symbol, String]) }
      def dependency_set
        @dependency_set ||=
          T.let(
            dependencies.first
              &.requirements
              &.find { |r| r.dig(:metadata, :dependency_set) }
              &.dig(:metadata, :dependency_set),
            T.nilable(T.nilable(T::Hash[Symbol, String]))
          )

        raise "No dependency set!" unless @dependency_set

        @dependency_set
      end

      sig { returns(T::Array[String]) }
      def dependency_links
        return T.must(@dependency_links) if defined?(@dependency_links)

        uniq_deps = dependencies.each_with_object({}) { |dep, memo| memo[dep.name] ||= dep }.values
        @dependency_links = uniq_deps.map { |dep| dependency_link(dep) }
      end

      sig { params(directory: String).returns(T.nilable(T::Array[String])) }
      def dependency_links_for_directory(directory)
        dependencies_in_directory = dependencies.select { |dep| dep.metadata[:directory] == directory }
        uniq_deps = dependencies_in_directory.each_with_object({}) { |dep, memo| memo[dep.name] ||= dep }.values
        @dependency_links = T.let(uniq_deps.map { |dep| dependency_link(dep) }, T.nilable(T::Array[String]))
      end

      sig { params(dependency: Dependabot::Dependency).returns(String) }
      def dependency_link(dependency)
        if source_url(dependency)
          "[#{dependency.display_name}](#{source_url(dependency)})"
        elsif homepage_url(dependency)
          "[#{dependency.display_name}](#{homepage_url(dependency)})"
        else
          dependency.display_name
        end
      end

      sig { params(dependency: Dependabot::Dependency).returns(String) }
      def dependency_version_update(dependency)
        "#{dependency.humanized_previous_version} to #{dependency.humanized_version}"
      end

      sig { returns(String) }
      def metadata_links
        return metadata_links_for_dep(T.must(dependencies.first)) if dependencies.count == 1 && dependency_group.nil?

        dependencies.map do |dep|
          if dep.removed?
            "\n\nRemoves `#{dep.display_name}`"
          else
            "\n\nUpdates `#{dep.display_name}` " \
              "#{from_version_msg(dep.humanized_previous_version)}to " \
              "#{dep.humanized_version}" \
              "#{metadata_links_for_dep(dep)}"
          end
        end.join
      end

      sig { params(dep: Dependabot::Dependency).returns(String) }
      def metadata_links_for_dep(dep)
        msg = ""
        msg += "\n- [Release notes](#{releases_url(dep)})" if releases_url(dep)
        msg += "\n- [Changelog](#{changelog_url(dep)})" if changelog_url(dep)
        msg += "\n- [Upgrade guide](#{upgrade_url(dep)})" if upgrade_url(dep)
        msg += "\n- [Commits](#{commits_url(dep)})" if commits_url(dep)
        msg
      end

      sig { params(rows: T::Array[T::Array[String]]).returns(String) }
      def table(rows)
        [
          table_header(T.must(rows[0])),
          T.must(rows[1..]).map { |r| table_row(r) }
        ].join("\n")
      end

      sig { params(row: T::Array[String]).returns(String) }
      def table_header(row)
        [
          table_row(row),
          table_row(["---"] * row.count)
        ].join("\n")
      end

      sig { params(row: T::Array[String]).returns(String) }
      def table_row(row)
        "| #{row.join(' | ')} |"
      end

      sig { returns(String) }
      def metadata_cascades # rubocop:disable Metrics/PerceivedComplexity
        return metadata_cascades_for_dep(T.must(dependencies.first)) if dependencies.one? && !dependency_group

        dependencies.map do |dep|
          msg = if dep.removed?
                  "\nRemoves `#{dep.display_name}`\n"
                else
                  "\nUpdates `#{dep.display_name}` " \
                    "#{from_version_msg(dep.humanized_previous_version)}" \
                    "to #{dep.humanized_version}"
                end

          if vulnerabilities_fixed[dep.name]&.one?
            msg += " **This update includes a security fix.**"
          elsif vulnerabilities_fixed[dep.name]&.any?
            msg += " **This update includes security fixes.**"
          end

          msg + metadata_cascades_for_dep(dep)
        end.join
      end

      sig { params(dependency: Dependabot::Dependency).returns(String) }
      def metadata_cascades_for_dep(dependency)
        return "" if dependency.removed?

        MetadataPresenter.new(
          dependency: dependency,
          source: source,
          metadata_finder: metadata_finder(dependency),
          vulnerabilities_fixed: vulnerabilities_fixed[dependency.name],
          github_redirection_service: github_redirection_service
        ).to_s
      end

      sig { returns(String) }
      def ignore_conditions_table
        # Return an empty string if ignore_conditions is empty
        return "" if @ignore_conditions.empty?

        # Filter out the conditions where from_config_file is false and dependency is in @dependencies
        valid_ignore_conditions = @ignore_conditions.select do |ic|
          ic["source"] =~ /\A@dependabot ignore/ && dependencies.any? { |dep| dep.name == ic["dependency-name"] }
        end

        # Return an empty string if no valid ignore conditions after filtering
        return "" if valid_ignore_conditions.empty?

        # Sort them by updated_at, taking the latest 20
        sorted_ignore_conditions = valid_ignore_conditions.sort_by do |ic|
          ic["updated-at"].nil? ? Time.at(0).iso8601 : T.must(ic["updated-at"])
        end.last(20)

        # Map each condition to a row string
        table_rows = sorted_ignore_conditions.map do |ic|
          "| #{ic['dependency-name']} | [#{ic['version-requirement']}] |"
        end

        summary = "Most Recent Ignore Conditions Applied to This Pull Request"
        build_table(summary, table_rows)
      end

      sig { params(summary: String, rows: T::Array[String]).returns(String) }
      def build_table(summary, rows)
        table_header = "| Dependency Name | Ignore Conditions |"
        table_divider = "| --- | --- |"
        table_body = rows.join("\n")
        body = "\n#{[table_header, table_divider, table_body].join("\n")}\n"

        if %w(azure bitbucket codecommit).include?(source.provider)
          "\n##{summary}\n\n#{body}"
        else
          # Build the collapsible section
          msg = "<details>\n<summary>#{summary}</summary>\n\n" \
                "#{[table_header, table_divider, table_body].join("\n")}\n</details>"
          "\n#{msg}\n"
        end
      end

      sig { params(dependency: Dependabot::Dependency).returns(T.nilable(String)) }
      def changelog_url(dependency)
        metadata_finder(dependency).changelog_url
      end

      sig { params(dependency: Dependabot::Dependency).returns(T.nilable(String)) }
      def commits_url(dependency)
        metadata_finder(dependency).commits_url
      end

      sig { params(dependency: Dependabot::Dependency).returns(T.nilable(String)) }
      def homepage_url(dependency)
        metadata_finder(dependency).homepage_url
      end

      sig { params(dependency: Dependabot::Dependency).returns(T.nilable(String)) }
      def releases_url(dependency)
        metadata_finder(dependency).releases_url
      end

      sig { params(dependency: Dependabot::Dependency).returns(T.nilable(String)) }
      def source_url(dependency)
        metadata_finder(dependency).source_url
      end

      sig { params(dependency: Dependabot::Dependency).returns(T.nilable(String)) }
      def upgrade_url(dependency)
        metadata_finder(dependency).upgrade_guide_url
      end

      sig { params(dependency: Dependabot::Dependency).returns(Dependabot::MetadataFinders::Base) }
      def metadata_finder(dependency)
        @metadata_finder ||= T.let({}, T.nilable(T::Hash[String, Dependabot::MetadataFinders::Base]))
        @metadata_finder[dependency.name] ||=
          MetadataFinders
          .for_package_manager(dependency.package_manager)
          .new(dependency: dependency, credentials: credentials)
      end

      sig { returns(Dependabot::PullRequestCreator::PrNamePrefixer) }
      def pr_name_prefixer
        @pr_name_prefixer ||=
          T.let(
            PrNamePrefixer.new(
              source: source,
              dependencies: dependencies,
              credentials: credentials,
              commit_message_options: commit_message_options,
              security_fix: vulnerabilities_fixed.values.flatten.any?
            ),
            T.nilable(Dependabot::PullRequestCreator::PrNamePrefixer)
          )
      end

      sig { params(dependency: Dependabot::Dependency).returns(T.nilable(String)) }
      def old_library_requirement(dependency)
        old_reqs =
          T.must(dependency.previous_requirements) - dependency.requirements

        gemspec =
          old_reqs.find { |r| r[:file].match?(%r{^[^/]*\.gemspec$}) }
        return gemspec.fetch(:requirement) if gemspec

        req = T.must(old_reqs.first).fetch(:requirement)
        return req if req

        dependency.previous_ref if dependency.ref_changed?
      end

      sig { params(dependency: Dependabot::Dependency).returns(String) }
      def new_library_requirement(dependency)
        updated_reqs =
          dependency.requirements - T.must(dependency.previous_requirements)

        gemspec =
          updated_reqs.find { |r| r[:file].match?(%r{^[^/]*\.gemspec$}) }
        return gemspec.fetch(:requirement) if gemspec

        req = T.must(updated_reqs.first).fetch(:requirement)
        return req if req
        return T.must(dependency.new_ref) if dependency.ref_changed? && dependency.new_ref

        raise "No new requirement!"
      end

      # TODO: Bring this in line with existing library checks that we do in the
      # update checkers, which are also overridden by passing an explicit
      # `requirements_update_strategy`.
      #
      # TODO reuse in BranchNamer
      sig { returns(T::Boolean) }
      def library?
        # Reject any nested child gemspecs/vendored git dependencies
        root_files = files.map(&:name)
                          .select { |p| Pathname.new(p).dirname.to_s == "." }
        return true if root_files.any? { |nm| nm.end_with?(".gemspec") }

        dependencies.any? { |d| d.humanized_previous_version.nil? }
      end

      sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
      def switching_from_ref_to_release?(dependency)
        unless dependency.previous_version&.match?(/^[0-9a-f]{40}$/) ||
               (dependency.previous_version.nil? && dependency.previous_ref)
          return false
        end

        Gem::Version.correct?(dependency.version)
      end

      sig { returns(String) }
      def package_manager
        @package_manager ||= T.let(
          T.must(dependencies.first).package_manager,
          T.nilable(String)
        )
      end

      sig { params(method: String, err: StandardError).void }
      def suppress_error(method, err)
        Dependabot.logger.error("Error while generating #{method}: #{err.message}")
        Dependabot.logger.error(err.backtrace&.join("\n"))
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
