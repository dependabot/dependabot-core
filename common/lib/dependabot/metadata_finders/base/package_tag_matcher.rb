# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module MetadataFinders
    class Base
      # Tells a tag for the dependency apart from a tag for another package in the same repository.
      # Monorepos often tag each package as `<package>@<version>`, and other packages' names can start
      # with the dependency's name (`@scope/name` and `@scope/name-types`), so a plain prefix or
      # substring match on the name picks the wrong package.
      module PackageTagMatcher
        extend T::Sig

        # `<package>@<version>`, where the package name may have an npm scope.
        PACKAGE_TAG = %r{\A(?<package>(?:@[^@/\s]+/)?[^@/\s]+)@v?\d}

        # Whether the tag starts with the dependency's name, followed by a version.
        sig { params(tag: String, dependency_name: String).returns(T::Boolean) }
        def self.starts_with_dependency?(tag, dependency_name)
          tag.match?(/\A#{name_then_version(dependency_name)}/i)
        end

        # Whether the tag contains the dependency's name, followed by a version.
        sig { params(tag: String, dependency_name: String).returns(T::Boolean) }
        def self.contains_dependency?(tag, dependency_name)
          tag.match?(/#{name_then_version(dependency_name)}/i)
        end

        # Whether the tag has the `<package>@<version>` form for a package other than the dependency.
        sig { params(tag: String, dependency_name: String).returns(T::Boolean) }
        def self.other_package_tag?(tag, dependency_name)
          package = tag.match(PACKAGE_TAG)&.[](:package)
          return false unless package

          package.casecmp(dependency_name) != 0
        end

        # Whether the tag ends with exactly this version (`v3.24.0` for 3.24.0, but not `v3.24`).
        sig { params(tag: String, version: String).returns(T::Boolean) }
        def self.exact_version_tag?(tag, version)
          tag.match?(/(?:\A|[^0-9.])#{Regexp.escape(version)}\z/)
        end

        # Leaves out other packages' `<package>@<version>` tags, unless that would leave nothing.
        sig { params(tags: T::Array[String], dependency_name: String).returns(T::Array[String]) }
        def self.without_other_packages(tags, dependency_name)
          own_tags = tags.reject { |t| other_package_tag?(t, dependency_name) }
          own_tags.any? ? own_tags : tags
        end

        # Among tags for the same version, picks the dependency's own tag: tags of other packages are left
        # out, then a tag naming the dependency comes first, then one with exactly this version (`v3.24.0`
        # before a floating `v3.24`), then the shortest. The tag itself breaks any remaining tie, so the
        # result does not depend on the order the tags were listed in.
        sig do
          params(tags: T::Array[String], dependency_name: String, version: T.nilable(String))
            .returns(T.nilable(String))
        end
        def self.preferred_tag(tags, dependency_name, version)
          without_other_packages(tags, dependency_name).min_by do |t|
            [
              contains_dependency?(t, dependency_name) ? 0 : 1,
              version && exact_version_tag?(t, version) ? 0 : 1,
              t.length,
              t
            ]
          end
        end

        # The name, an optional separator, an optional `v`, then a digit: `name@1.2`, `name-1.2`,
        # `name.1.2`, `name/v1.2`. Requiring the digit stops `name` from matching `name-types@1.2`.
        sig { params(dependency_name: String).returns(String) }
        def self.name_then_version(dependency_name)
          "#{Regexp.escape(dependency_name)}[@/._-]?v?\\d"
        end
        private_class_method :name_then_version
      end
    end
  end
end
