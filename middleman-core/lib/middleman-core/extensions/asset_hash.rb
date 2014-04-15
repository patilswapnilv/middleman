require 'middleman-core/util'

class Middleman::Extensions::AssetHash < ::Middleman::Extension
  option :exts, %w(.jpg .jpeg .png .gif .js .css .otf .woff .eot .ttf .svg), 'List of extensions that get asset hashes appended to them.'
  option :ignore, [], 'Regexes of filenames to skip adding asset hashes to'
  option :format, ':basename-:digest.:ext', 'Format of renamed file.'
  option :keep_original, false, 'Whether the original file name should exist along side the hashed version.'

  def initialize(app, options_hash={}, &block)
    super

    require 'digest/sha1'
    require 'rack/mock'
    require 'uri'
    require 'middleman-core/middleware/inline_url_rewriter'
  end

  def after_configuration
    # Allow specifying regexes to ignore, plus always ignore apple touch icons
    @ignore = Array(options.ignore) + [/^apple-touch-icon/]

    app.use ::Middleman::Middleware::InlineURLRewriter,
      :url_extensions    => options.exts,
      :source_extensions => %w(.htm .html .php .css .js),
      :ignore            => @ignore,
      :middleman_app     => app,
      :proc              => method(:rewrite_url)
  end

  def rewrite_url(asset_path, dirpath)
    relative_path = Pathname.new(asset_path).relative?

    full_asset_path = if relative_path
      dirpath.join(asset_path).to_s
    else
      asset_path
    end

    if asset_page = app.sitemap.find_resource_by_path(full_asset_path)
      replacement_path = "/#{asset_page.destination_path}"
      replacement_path = Pathname.new(replacement_path).relative_path_from(dirpath).to_s if relative_path

      replacement_path
    end
  end

  # Update the main sitemap resource list
  # @return [void]
  def manipulate_resource_list(resources)
    @rack_client = ::Rack::MockRequest.new(app.class.to_rack_app)

    proxied_renames = []

    # Process resources in order: binary images and fonts, then SVG, then JS/CSS.
    # This is so by the time we get around to the text files (which may reference
    # images and fonts) the static assets' hashes are already calculated.
    sorted_resources = resources.sort_by do |a|
      if %w(.svg).include? a.ext
        0
      elsif %w(.js .css).include? a.ext
        1
      else
        -1
      end
    end.each do |resource|
      next unless options.exts.include?(resource.ext)
      next if ignored_resource?(resource)
      next if resource.ignored?

      new_name = hashed_filename(resource)

      if options.keep_original
        p = ::Middleman::Sitemap::Resource.new(
          app.sitemap,
          new_name
        )
        p.proxy_to(resource.path)

        proxied_renames << p
      else
        resource.destination_path = new_name
      end
    end

    sorted_resources + proxied_renames
  end

  def hashed_filename(resource)
    # Render through the Rack interface so middleware and mounted apps get a shot
    response = @rack_client.get(URI.escape(resource.destination_path), { 'bypass_inline_url_rewriter' => 'true' })
    raise "#{resource.path} should be in the sitemap!" unless response.status == 200

    digest = Digest::SHA1.hexdigest(response.body)[0..7]

    file_name = File.basename(resource.destination_path)
    path = resource.destination_path.split(file_name).first

    ext_without_leading_period = resource.ext.sub(/^\./, '')

    base_name = File.basename(file_name, resource.ext)

    path + options.format.dup
      .gsub(/:basename/, base_name)
      .gsub(/:digest/, digest)
      .gsub(/:ext/, ext_without_leading_period)
  end

  def ignored_resource?(resource)
    @ignore.any? { |ignore| Middleman::Util.path_match(ignore, resource.destination_path) }
  end

end

# =================Temp Generate Test data==============================
#   ["jpg", "png", "gif"].each do |ext|
#     [["<p>", "</p>"], ["<p><img src=", " /></p>"], ["<p>background-image:url(", ");</p>"]].each do |outer|
#       [["",""], ["'", "'"], ['"','"']].each do |inner|
#         [["", ""], ["/", ""], ["../", ""], ["../../", ""], ["../../../", ""], ["http://example.com/", ""], ["a","a"], ["1","1"], [".", "."], ["-","-"], ["_","_"]].each do |path_parts|
#           name = 'images/100px.'
#           puts outer[0] + inner[0] + path_parts[0] + name + ext + path_parts[1] + inner[1] + outer[1]
#         end
#       end
#     end
#     puts "<br /><br /><br />"
#   end
