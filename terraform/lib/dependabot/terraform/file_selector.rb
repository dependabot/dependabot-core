# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module FileSelector
  extend T::Sig
  extend T::Helpers

  abstract!

  sig { abstract.returns(T::Array[Dependabot::DependencyFile]) }
  def dependency_files; end

  private

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  def terraform_files
    dependency_files.select { |f| f.name.end_with?(".tf") }
  end

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  def terragrunt_files
    dependency_files.select { |f| terragrunt_file?(f.name) }
  end

  sig { params(file_name: String).returns(T::Boolean) }
  def terragrunt_file?(file_name)
    !lockfile?(file_name) && file_name.end_with?(".hcl")
  end

  sig { params(filename: String).returns(T::Boolean) }
  def lockfile?(filename)
    filename == ".terraform.lock.hcl"
  end

  sig { returns(T.nilable(Dependabot::DependencyFile)) }
  def lockfile
    dependency_files.find { |f| lockfile?(f.name) }
  end
end
