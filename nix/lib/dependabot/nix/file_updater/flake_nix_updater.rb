# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/nix/file_updater"

module Dependabot
  module Nix
    class FileUpdater < Dependabot::FileUpdaters::Base
      # Updates branch/ref references in flake.nix for nixpkgs inputs.
      #
      # Handles URL patterns like:
      #   inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";
      #   nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";
      #   url = "github:NixOS/nixpkgs/nixos-23.05";
      class FlakeNixUpdater
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            flake_nix_content: String
          ).void
        end
        def initialize(dependency:, flake_nix_content:)
          @dependency = dependency
          @flake_nix_content = flake_nix_content
        end

        sig { returns(String) }
        def updated_content
          old_branch = previous_branch
          new_branch = current_branch
          return flake_nix_content unless old_branch && new_branch
          return flake_nix_content if old_branch == new_branch

          updated = flake_nix_content.gsub(
            nixpkgs_url_pattern(old_branch),
            nixpkgs_url_replacement(new_branch)
          )

          if updated == flake_nix_content
            raise Dependabot::DependencyFileContentNotChanged,
                  "Expected flake.nix to change for #{dependency.name}, but it didn't"
          end

          updated
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(String) }
        attr_reader :flake_nix_content

        sig { returns(T.nilable(String)) }
        def previous_branch
          dependency.previous_requirements&.first&.dig(:source, :ref)
        end

        sig { returns(T.nilable(String)) }
        def current_branch
          dependency.requirements.first&.dig(:source, :ref)
        end

        # Matches a github flake URL containing the old branch ref.
        # Captures the prefix so we can preserve it in the replacement.
        sig { params(branch: String).returns(Regexp) }
        def nixpkgs_url_pattern(branch)
          escaped = Regexp.escape(branch)
          %r{(github:NixOS/nixpkgs/)#{escaped}(?=")}i
        end

        sig { params(branch: String).returns(String) }
        def nixpkgs_url_replacement(branch)
          "\\1#{branch}"
        end
      end
    end
  end
end
