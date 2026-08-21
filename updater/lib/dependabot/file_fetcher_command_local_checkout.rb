# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module FileFetcherCommandLocalCheckout
    extend T::Sig
    extend T::Helpers

    abstract!

    private

    sig { abstract.void }
    def validate_target_branch; end

    sig { abstract.void }
    def dependabot_ref_namespace_available?; end

    sig { abstract.returns(T::Boolean) }
    def already_cloned?; end

    sig { void }
    def validate_repository
      validate_local_checkout
      return if local_checkout_only?

      validate_target_branch
      dependabot_ref_namespace_available?
    end

    sig { void }
    def validate_local_checkout
      return unless local_checkout_only?

      repo_contents_path = Environment.repo_contents_path
      Kernel.raise "DEPENDABOT_REPO_CONTENTS_PATH is not set" if repo_contents_path.to_s.empty?
      return if already_cloned?

      Kernel.raise "Local repository checkout not found at #{repo_contents_path}"
    end

    sig { returns(T::Boolean) }
    def local_checkout_only?
      ENV["DEPENDABOT_LOCAL_CHECKOUT_ONLY"] == "true"
    end
  end
end
