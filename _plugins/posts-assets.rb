class PostFile < Jekyll::StaticFile
    def initialize(site, base, dir, name, dest)
      super(site, base, dir, name)
      @name = name
      @dest = dest
    end

    # Obtain destination path.
    #
    # dest - The String path to the destination dir.
    #
    # Returns destination file path.
    def destination(_dest)
      File.join(@dest, @name)
    end
  end

# class CopyPostAssets < Jekyll::Generator
#     def generate(site)
#         post_directory = File.join(site.source, '_posts') # Path to _posts directory
#             Dir.glob(File.join(post_directory, '**', '*')) do |asset|
#                 next unless File.file?(asset)             # Skip directories
#                 next if File.extname(asset) == ".md"      # Skip .md files
#                 relative_path = asset.sub(post_directory + '/', '') # Get the relative path

#                 static_file = PostFile.new(site, post_directory, "", relative_path, ("posts" + relative_path).to_path())
#                 site.static_files << static_file
#                 # puts "Marked for future copy: #{asset} to #{File.join(site.dest, relative_path)}"
#         end
#     end
# end

class PostFileGenerator < Jekyll::Generator
    FIXED_DATE_FILENAME_MATCHER = %r!^(?:.+/)*(\d{2,4}-\d{1,2}-\d{1,2})-([^/]*)(\.[^.]+)$!.freeze

    # _posts/
    #   2018-01-01-whatever.md     # there's a date on this filename, so it will be treated as a post
    #                              # it's a direct descendant of _posts, so we do not treat it as an asset root
    #   somedir/
    #     2018-05-01-some-post.md  # there's a date on this filename, so it will be treated as a post.
    #                              # moreover, we will treat its dir as an asset root
    #     cool.svg                 # there's no date on this filename, so it will be treated as an asset
    #     undated.md               # there's no date on this filename, so it will be treated as an asset
    #     img/
    #       cool.png               # yes, even deeply-nested files are eligible to be copied.
    def generate(site)
      site_srcroot = Pathname.new site.source
      posts_src_dir = site_srcroot + "_posts"
      drafts_src_dir = site_srcroot + "_drafts"

      docs_with_dirs = site.posts.docs
        .reject do |doc|
          Pathname.new(doc.path).dirname.instance_eval do |dirname|
            [posts_src_dir, drafts_src_dir].reduce(false) do |acc, dir|
              acc || dirname.eql?(dir)
            end
          end
        end

      assets = docs_with_dirs.map do |doc|
        dest_dir = Pathname.new(doc.destination("")).dirname
        Pathname.new(doc.path).dirname.instance_eval do |postdir|
          Dir[postdir + "**/*"]
            .reject { |fname| fname =~ FIXED_DATE_FILENAME_MATCHER }
            .reject { |fname| File.directory? fname }
            .map do |fname|
              asset_abspath = Pathname.new fname
              srcroot_to_asset = asset_abspath.relative_path_from(site_srcroot)
              srcroot_to_assetdir = srcroot_to_asset.dirname
              asset_basename = srcroot_to_asset.basename

              assetdir_abs = site_srcroot + srcroot_to_assetdir
              postdir_to_assetdir = assetdir_abs.relative_path_from(postdir)
              PostFile.new(site, site_srcroot, srcroot_to_assetdir.to_path, asset_basename, (dest_dir + postdir_to_assetdir).to_path)
            end
        end
      end.flatten

      site.static_files.concat(assets)
    end
  end