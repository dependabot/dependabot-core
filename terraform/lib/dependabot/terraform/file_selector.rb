# frozen_string_literal: true

module FileSelector
  private

  def terraform_files
    dependency_files.select { |f| f.name.end_with?(".tf") }
  end

  def terragrunt_files
    dependency_files.select { |f| terragrunt_file?(f.name) }
  end

  def terragrunt_file?(file_name)
    file_name != ".terraform.lock.hcl" && file_name.end_with?(".hcl")
  end

  def lock_file?
    !lock_file.nil?
  end

  def lock_file
    dependency_files.find { |f| f.name == ".terraform.lock.hcl" }
  end
end
