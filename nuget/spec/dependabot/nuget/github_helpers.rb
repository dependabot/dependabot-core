# typed: false
# frozen_string_literal: true

require "digest/sha1"

module GitHubHelpers
  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/ParameterLists
  def self.stub_requests_for_directory(stub_callback, path_on_disk, relative_path, url_base, authorization, org_name,
                                       repo_name, branch_name)
    url = "#{url_base}#{relative_path}?ref=sha"
    stub_callback.call(:get, url)
                 .with(headers: { "Authorization" => authorization })
                 .to_return(
                   status: 200,
                   body: GitHubHelpers.create_tree_object(
                     path_on_disk,
                     relative_path,
                     org_name,
                     repo_name,
                     branch_name
                   ).to_json,
                   headers: { "content-type" => "application/json" }
                 )

    Dir.entries(path_on_disk).select { |entry| entry != "." && entry != ".." }.each do |entry|
      full_path = File.join(path_on_disk, entry)
      current_relative_path = relative_path == "" ? entry : File.join(relative_path, entry)
      url = "#{url_base}#{current_relative_path}?ref=sha"
      if File.directory?(full_path)
        stub_requests_for_directory(stub_callback, full_path, current_relative_path, url_base, authorization, org_name,
                                    repo_name, branch_name)
      else
        stub_callback.call(:get, url)
                     .with(headers: { "Authorization" => authorization })
                     .to_return(
                       status: 200,
                       body: GitHubHelpers.create_file_object(
                         current_relative_path,
                         File.read(full_path),
                         org_name,
                         repo_name,
                         branch_name
                       ).to_json,
                       headers: { "content-type" => "application/json" }
                     )
      end
    end
  end
  # rubocop:enable Metrics/ParameterLists
  # rubocop:enable Metrics/MethodLength

  def self.create_file_object(path, content, org_name, repo_name, branch_name)
    hash = hash_file_content(content)
    obj = {
      "name" => File.basename(path),
      "path" => path,
      "sha" => hash,
      "size" => content.length,
      "url" => "https://api.github.com/repos/#{org_name}/#{repo_name}/contents/#{path}?ref=#{branch_name}",
      "html_url" => "https://github.com/#{org_name}/#{repo_name}/blob/#{branch_name}/#{path}",
      "git_url" => "https://api.github.com/repos/#{org_name}/#{repo_name}/git/blobs/#{hash}",
      "download_url" => "https://raw.githubusercontent.com/#{org_name}/#{repo_name}/#{branch_name}/#{path}",
      "type" => "file",
      "content" => Base64.encode64(content),
      "encoding" => "base64",
      "_links" => {
        "self" => "https://api.github.com/repos/#{org_name}/#{repo_name}/contents/#{path}?ref=#{branch_name}",
        "git" => "https://api.github.com/repos/#{org_name}/#{repo_name}/git/blobs/#{hash}",
        "html" => "https://github.com/#{org_name}/#{repo_name}/blob/#{branch_name}/#{path}}"
      }
    }
    obj
  end

  # rubocop:disable Metrics/MethodLength
  def self.create_tree_object(directory_path, relative_path, org_name, repo_name, branch_name)
    result =
      Dir.entries(directory_path).select { |entry| entry != "." && entry != ".." }.map do |entry|
        path = File.join(directory_path, entry)
        if File.directory?(path)
          type = "dir"
          obj_type = "tree"
          sha = hash_tree_content(path)
          size = 0
          download_url = nil
        else
          type = "file"
          obj_type = "blob"
          content = File.read(path)
          sha = hash_file_content(content)
          size = content.length
          download_url = "https://raw.githubusercontent.com/#{org_name}/#{repo_name}/#{branch_name}/#{path}"
        end
        obj = {
          "name" => entry,
          "path" => relative_path,
          "sha" => sha,
          "size" => size,
          "url" => "https://api.github.com/repos/#{org_name}/#{repo_name}/contents/#{path}?ref=#{branch_name}",
          "html_url" => "https://github.com/#{org_name}/#{repo_name}/#{obj_type}/#{branch_name}/#{path}",
          "git_url" => "https://api.github.com/repos/#{org_name}/#{repo_name}/git/#{obj_type}s/#{sha}",
          "download_url" => download_url,
          "type" => type,
          "_links" => {
            "self" => "https://api.github.com/repos/#{org_name}/#{repo_name}/contents/#{path}?ref=#{branch_name}",
            "git" => "https://api.github.com/repos/#{org_name}/#{repo_name}/git/#{obj_type}s/#{sha}",
            "html" => "https://github.com/#{org_name}/#{repo_name}/#{obj_type}/#{branch_name}/#{path}"
          }
        }
        obj
      end
    result
  end
  # rubocop:enable Metrics/MethodLength

  def self.hash_file_content(content)
    raw_content = "blob #{content.length}\0#{content}"
    Digest::SHA1.hexdigest(raw_content)
  end

  def self.hash_tree_content(directory)
    tree_content =
      Dir.entries(directory).select { |entry| entry != "." && entry != ".." }.map do |entry|
        path = File.join(directory, entry)
        if File.directory?(path)
          "040000 tree #{hash_tree_content(path)}\t#{entry}"
        else
          content = File.read(path)
          "100644 blob #{hash_file_content(content)}\t#{entry}"
        end
      end.join("\n")
    Digest::SHA1.hexdigest("tree #{tree_content.length}\0#{tree_content}")
  end
end
