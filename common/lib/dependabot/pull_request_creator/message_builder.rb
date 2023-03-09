# frozen_string_literal: true

require "pathname"
require "dependabot/clients/github_with_retries"
require "dependabot/clients/gitlab_with_retries"
require "dependabot/logger"
require "dependabot/metadata_finders"
require "dependabot/pull_request_creator"
require "dependabot/pull_request_creator/message"

# rubocop:disable Metrics/ClassLength
module Dependabot
  class PullRequestCreator
    # MessageBuilder builds PR message for a dependency update
    class MessageBuilder
      require_relative "message_builder/metadata_presenter"
      require_relative "message_builder/issue_linker"
      require_relative "message_builder/link_and_mention_sanitizer"
      require_relative "pr_name_prefixer"

      attr_reader :source, :dependencies, :files, :credentials,
                  :pr_message_header, :pr_message_footer,
                  :commit_message_options, :vulnerabilities_fixed,
                  :github_redirection_service

      def initialize(source:, dependencies:, files:, credentials:,
                     pr_message_header: nil, pr_message_footer: nil,
                     commit_message_options: {}, vulnerabilities_fixed: {},
                     github_redirection_service: DEFAULT_GITHUB_REDIRECTION_SERVICE)
        @dependencies               = dependencies
        @files                      = files
        @source                     = source
        @credentials                = credentials
        @pr_message_header          = pr_message_header
        @pr_message_footer          = pr_message_footer
        @commit_message_options     = commit_message_options
        @vulnerabilities_fixed      = vulnerabilities_fixed
        @github_redirection_service = github_redirection_service
      end

      def pr_name
        begin
          pr_name = pr_name_prefixer.pr_name_prefix
        rescue StandardError => e
          Dependabot.logger.error("Error while generating PR name: #{e.message}")
          pr_name = ""
        end
        pr_name += library? ? library_pr_name : application_pr_name
        return pr_name if files.first.directory == "/"

        pr_name + " in #{files.first.directory}"
      end

      def pr_message
        suffixed_pr_message_header + commit_message_intro + \
          metadata_cascades + prefixed_pr_message_footer
      rescue StandardError => e
        Dependabot.logger.error("Error while generating PR message: #{e.message}")
        suffixed_pr_message_header + prefixed_pr_message_footer
      end

      def commit_message
        message = commit_subject + "\n\n"
        message += commit_message_intro
        message += metadata_links
        message += "\n\n" + message_trailers if message_trailers
        message
      rescue StandardError => e
        Dependabot.logger.error("Error while generating commit message: #{e.message}")
        message = commit_subject
        message += "\n\n" + message_trailers if message_trailers
        message
      end

      def message
        Dependabot::PullRequestCreator::Message.new(
          pr_name: pr_name,
          pr_message: pr_message,
          commit_message: commit_message
        )
      end

      private

      def library_pr_name
        pr_name = "update "
        pr_name = pr_name.capitalize if pr_name_prefixer.capitalize_first_word?

        pr_name +
          if dependencies.count == 1
            "#{dependencies.first.display_name} requirement " \
              "#{from_version_msg(old_library_requirement(dependencies.first))}" \
              "to #{new_library_requirement(dependencies.first)}"
          else
            names = dependencies.map(&:name).uniq
            if names.count == 1
              "requirements for #{names.first}"
            else
              "requirements for #{names[0..-2].join(', ')} and #{names[-1]}"
            end
          end
      end

      # rubocop:disable Metrics/AbcSize
      def application_pr_name
        pr_name = "bump "
        pr_name = pr_name.capitalize if pr_name_prefixer.capitalize_first_word?

        pr_name +
          if dependencies.count == 1
            dependency = dependencies.first
            "#{dependency.display_name} " \
              "#{from_version_msg(previous_version(dependency))}" \
              "to #{new_version(dependency)}"
          elsif updating_a_property?
            dependency = dependencies.first
            "#{property_name} " \
              "#{from_version_msg(previous_version(dependency))}" \
              "to #{new_version(dependency)}"
          elsif updating_a_dependency_set?
            dependency = dependencies.first
            "#{dependency_set.fetch(:group)} dependency set " \
              "#{from_version_msg(previous_version(dependency))}" \
              "to #{new_version(dependency)}"
          else
            names = dependencies.map(&:name).uniq
            if names.count == 1
              names.first
            else
              "#{names[0..-2].join(', ')} and #{names[-1]}"
            end
          end
      end
      # rubocop:enable Metrics/AbcSize

      def pr_name_prefix
        pr_name_prefixer.pr_name_prefix
      end

      def commit_subject
        subject = pr_name.gsub("⬆️", ":arrow_up:").gsub("🔒", ":lock:")
        return subject unless subject.length > 72

        subject = subject.gsub(/ from [^\s]*? to [^\s]*/, "")
        return subject unless subject.length > 72

        subject.split(" in ").first
      end

      def commit_message_intro
        return requirement_commit_message_intro if library?

        version_commit_message_intro
      end

      def prefixed_pr_message_footer
        return "" unless pr_message_footer

        "\n\n#{pr_message_footer}"
      end

      def suffixed_pr_message_header
        return "" unless pr_message_header

        "#{pr_message_header}\n\n"
      end

      def message_trailers
        return unless signoff_trailers || custom_trailers

        [signoff_trailers, custom_trailers].compact.join("\n")
      end

      def custom_trailers
        trailers = commit_message_options[:trailers]
        return if trailers.nil?
        raise("Commit trailers must be a Hash object") unless trailers.is_a?(Hash)

        trailers.compact.map { |k, v| "#{k}: #{v}" }.join("\n")
      end

      def signoff_trailers
        return unless on_behalf_of_message || signoff_message

        [on_behalf_of_message, signoff_message].compact.join("\n")
      end

      def signoff_message
        signoff_details = commit_message_options[:signoff_details]
        return unless signoff_details.is_a?(Hash)
        return unless signoff_details[:name] && signoff_details[:email]

        "Signed-off-by: #{signoff_details[:name]} <#{signoff_details[:email]}>"
      end

      def on_behalf_of_message
        signoff_details = commit_message_options[:signoff_details]
        return unless signoff_details.is_a?(Hash)
        return unless signoff_details[:org_name] && signoff_details[:org_email]

        "On-behalf-of: @#{signoff_details[:org_name]} " \
          "<#{signoff_details[:org_email]}>"
      end

      def requirement_commit_message_intro
        msg = "Updates the requirements on "

        msg +=
          if dependencies.count == 1
            "#{dependency_links.first} "
          else
            "#{dependency_links[0..-2].join(', ')} and #{dependency_links[-1]} "
          end

        msg + "to permit the latest version."
      end

      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/AbcSize
      def version_commit_message_intro
        return multidependency_property_intro if dependencies.count > 1 && updating_a_property?

        return dependency_set_intro if dependencies.count > 1 && updating_a_dependency_set?

        return transitive_removed_dependency_intro if dependencies.count > 1 && removing_a_transitive_dependency?

        return transitive_multidependency_intro if dependencies.count > 1 &&
                                                   updating_top_level_and_transitive_dependencies?

        return multidependency_intro if dependencies.count > 1

        dependency = dependencies.first
        msg = "Bumps #{dependency_links.first} " \
              "#{from_version_msg(previous_version(dependency))}" \
              "to #{new_version(dependency)}."

        msg += " This release includes the previously tagged commit." if switching_from_ref_to_release?(dependency)

        if vulnerabilities_fixed[dependency.name]&.one?
          msg += " **This update includes a security fix.**"
        elsif vulnerabilities_fixed[dependency.name]&.any?
          msg += " **This update includes security fixes.**"
        end

        msg
      end

      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/AbcSize

      def multidependency_property_intro
        dependency = dependencies.first

        "Bumps `#{property_name}` " \
          "#{from_version_msg(previous_version(dependency))}" \
          "to #{new_version(dependency)}."
      end

      def dependency_set_intro
        dependency = dependencies.first

        "Bumps `#{dependency_set.fetch(:group)}` " \
          "dependency set #{from_version_msg(previous_version(dependency))}" \
          "to #{new_version(dependency)}."
      end

      def multidependency_intro
        "Bumps #{dependency_links[0..-2].join(', ')} " \
          "and #{dependency_links[-1]}. These " \
          "dependencies needed to be updated together."
      end

      def transitive_multidependency_intro
        dependency = dependencies.first

        msg = "Bumps #{dependency_links[0]} to #{new_version(dependency)}"

        msg += if dependencies.count > 2
                 " and updates ancestor dependencies #{dependency_links[0..-2].join(', ')} " \
                   "and #{dependency_links[-1]}. "
               else
                 " and updates ancestor dependency #{dependency_links[1]}. "
               end

        msg += "These dependencies need to be updated together.\n"

        msg
      end

      def transitive_removed_dependency_intro
        msg = "Removes #{dependency_links[0]}. It's no longer used after updating"

        msg += if dependencies.count > 2
                 " ancestor dependencies #{dependency_links[0..-2].join(', ')} " \
                   "and #{dependency_links[-1]}. "
               else
                 " ancestor dependency #{dependency_links[1]}. "
               end

        msg += "These dependencies need to be updated together.\n"

        msg
      end

      def from_version_msg(previous_version)
        return "" unless previous_version

        "from #{previous_version} "
      end

      def updating_a_property?
        dependencies.first.
          requirements.
          any? { |r| r.dig(:metadata, :property_name) }
      end

      def updating_a_dependency_set?
        dependencies.first.
          requirements.
          any? { |r| r.dig(:metadata, :dependency_set) }
      end

      def removing_a_transitive_dependency?
        dependencies.any?(&:removed?)
      end

      def updating_top_level_and_transitive_dependencies?
        dependencies.any?(&:top_level?) &&
          dependencies.any? { |dep| !dep.top_level? }
      end

      def property_name
        @property_name ||= dependencies.first.requirements.
                           find { |r| r.dig(:metadata, :property_name) }&.
                           dig(:metadata, :property_name)

        raise "No property name!" unless @property_name

        @property_name
      end

      def dependency_set
        @dependency_set ||= dependencies.first.requirements.
                            find { |r| r.dig(:metadata, :dependency_set) }&.
                            dig(:metadata, :dependency_set)

        raise "No dependency set!" unless @dependency_set

        @dependency_set
      end

      def dependency_links
        dependencies.map do |dependency|
          if source_url(dependency)
            "[#{dependency.display_name}](#{source_url(dependency)})"
          elsif homepage_url(dependency)
            "[#{dependency.display_name}](#{homepage_url(dependency)})"
          else
            dependency.display_name
          end
        end
      end

      def metadata_links
        return metadata_links_for_dep(dependencies.first) if dependencies.count == 1

        dependencies.map do |dep|
          if dep.removed?
            "\n\nRemoves `#{dep.display_name}`"
          else
            "\n\nUpdates `#{dep.display_name}` " \
              "#{from_version_msg(previous_version(dep))}to " \
              "#{new_version(dep)}" \
              "#{metadata_links_for_dep(dep)}"
          end
        end.join
      end

      def metadata_links_for_dep(dep)
        msg = ""
        msg += "\n- [Release notes](#{releases_url(dep)})" if releases_url(dep)
        msg += "\n- [Changelog](#{changelog_url(dep)})" if changelog_url(dep)
        msg += "\n- [Upgrade guide](#{upgrade_url(dep)})" if upgrade_url(dep)
        msg += "\n- [Commits](#{commits_url(dep)})" if commits_url(dep)
        msg
      end

      def metadata_cascades
        return metadata_cascades_for_dep(dependencies.first) if dependencies.one?

        dependencies.map do |dep|
          msg = if dep.removed?
                  "\nRemoves `#{dep.display_name}`\n"
                else
                  "\nUpdates `#{dep.display_name}` " \
                    "#{from_version_msg(previous_version(dep))}" \
                    "to #{new_version(dep)}"
                end

          if vulnerabilities_fixed[dep.name]&.one?
            msg += " **This update includes a security fix.**"
          elsif vulnerabilities_fixed[dep.name]&.any?
            msg += " **This update includes security fixes.**"
          end

          msg + metadata_cascades_for_dep(dep)
        end.join
      end

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

      def changelog_url(dependency)
        metadata_finder(dependency).changelog_url
      end

      def commits_url(dependency)
        metadata_finder(dependency).commits_url
      end

      def homepage_url(dependency)
        metadata_finder(dependency).homepage_url
      end

      def releases_url(dependency)
        metadata_finder(dependency).releases_url
      end

      def source_url(dependency)
        metadata_finder(dependency).source_url
      end

      def upgrade_url(dependency)
        metadata_finder(dependency).upgrade_guide_url
      end

      def metadata_finder(dependency)
        @metadata_finder ||= {}
        @metadata_finder[dependency.name] ||=
          MetadataFinders.
          for_package_manager(dependency.package_manager).
          new(dependency: dependency, credentials: credentials)
      end

      def pr_name_prefixer
        @pr_name_prefixer ||=
          PrNamePrefixer.new(
            source: source,
            dependencies: dependencies,
            credentials: credentials,
            commit_message_options: commit_message_options,
            security_fix: vulnerabilities_fixed.values.flatten.any?
          )
      end

      def previous_version(dependency)
        # If we don't have a previous version, we *may* still be able to figure
        # one out if a ref was provided and has been changed (in which case the
        # previous ref was essentially the version).
        if dependency.previous_version.nil?
          return ref_changed?(dependency) ? previous_ref(dependency) : nil
        end

        if dependency.previous_version.match?(/^[0-9a-f]{40}$/)
          return previous_ref(dependency) if ref_changed?(dependency) && previous_ref(dependency)

          "`#{dependency.previous_version[0..6]}`"
        elsif dependency.version == dependency.previous_version &&
              package_manager == "docker"
          digest = docker_digest_from_reqs(dependency.previous_requirements)
          "`#{digest.split(':').last[0..6]}`"
        else
          dependency.previous_version
        end
      end

      def new_version(dependency)
        if dependency.version.match?(/^[0-9a-f]{40}$/)
          return new_ref(dependency) if ref_changed?(dependency) && new_ref(dependency)

          "`#{dependency.version[0..6]}`"
        elsif dependency.version == dependency.previous_version &&
              package_manager == "docker"
          digest = docker_digest_from_reqs(dependency.requirements)
          "`#{digest.split(':').last[0..6]}`"
        else
          dependency.version
        end
      end

      def docker_digest_from_reqs(requirements)
        requirements.
          filter_map { |r| r.dig(:source, "digest") || r.dig(:source, :digest) }.
          first
      end

      def previous_ref(dependency)
        previous_refs = dependency.previous_requirements.filter_map do |r|
          r.dig(:source, "ref") || r.dig(:source, :ref)
        end.uniq
        return previous_refs.first if previous_refs.count == 1
      end

      def new_ref(dependency)
        new_refs = dependency.requirements.filter_map do |r|
          r.dig(:source, "ref") || r.dig(:source, :ref)
        end.uniq
        return new_refs.first if new_refs.count == 1
      end

      def old_library_requirement(dependency)
        old_reqs =
          dependency.previous_requirements - dependency.requirements

        gemspec =
          old_reqs.find { |r| r[:file].match?(%r{^[^/]*\.gemspec$}) }
        return gemspec.fetch(:requirement) if gemspec

        req = old_reqs.first.fetch(:requirement)
        return req if req
        return previous_ref(dependency) if ref_changed?(dependency)
      end

      def new_library_requirement(dependency)
        updated_reqs =
          dependency.requirements - dependency.previous_requirements

        gemspec =
          updated_reqs.find { |r| r[:file].match?(%r{^[^/]*\.gemspec$}) }
        return gemspec.fetch(:requirement) if gemspec

        req = updated_reqs.first.fetch(:requirement)
        return req if req
        return new_ref(dependency) if ref_changed?(dependency) && new_ref(dependency)

        raise "No new requirement!"
      end

      def ref_changed?(dependency)
        previous_ref(dependency) != new_ref(dependency)
      end

      # TODO: Bring this in line with existing library checks that we do in the
      # update checkers, which are also overriden by passing an explicit
      # `requirements_update_strategy`.
      #
      # TODO re-use in BranchNamer
      def library?
        # Reject any nested child gemspecs/vendored git dependencies
        root_files = files.map(&:name).
                     select { |p| Pathname.new(p).dirname.to_s == "." }
        return true if root_files.select { |nm| nm.end_with?(".gemspec") }.any?

        dependencies.any? { |d| previous_version(d).nil? }
      end

      def switching_from_ref_to_release?(dependency)
        unless dependency.previous_version&.match?(/^[0-9a-f]{40}$/) ||
               (dependency.previous_version.nil? && previous_ref(dependency))
          return false
        end

        Gem::Version.correct?(dependency.version)
      end

      def package_manager
        @package_manager ||= dependencies.first.package_manager
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
