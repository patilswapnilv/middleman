require 'middleman-core/util'
require 'rack'
require 'rack/response'

module Middleman
  module Middleware
    class InlineURLRewriter
      def initialize(app, options={})
        @rack_app               = app
        @middleman_app          = options[:middleman_app]

        @proc                   = options[:proc] || Proc.new { |path| path }

        @exts                   = options[:url_extensions]
        @exts_regex_text        = @exts.map {|e| Regexp.escape(e) }.join('|')

        @source_exts            = options[:source_extensions]
        @source_exts_regex_text = @source_exts.map {|e| Regexp.escape(e) }.join('|')

        @ignore                 = options[:ignore]
      end

      def call(env)
        status, headers, response = @rack_app.call(env)

        # We don't want to use this middleware when rendering files to figure out their hash!
        return [status, headers, response] if env['bypass_inline_url_rewriter'] == 'true'

        path = ::Middleman::Util.full_path(env['PATH_INFO'], @middleman_app)
    
        if path =~ /(^\/$)|(#{@source_exts_regex_text}$)/
          if body = ::Middleman::Util.extract_response_text(response)
            status, headers, response = ::Rack::Response.new(rewrite_paths(body, path), status, headers).finish
          end
        end

        [status, headers, response]
      end

    private

      def rewrite_paths(body, path)
        dirpath = Pathname.new(File.dirname(path))

        # TODO: This regex will change some paths in plan HTML (not in a tag) - is that OK?
        body.gsub(/([=\'\"\(]\s*)([^\s\'\"\)]+(#{@exts_regex_text}))/) do |match|
          opening_character = $1
          asset_path = $2

          relative_path = Pathname.new(asset_path).relative?

          full_asset_path = if relative_path
            dirpath.join(asset_path).to_s
          else
            asset_path
          end

          if @ignore.any? { |r| full_asset_path.match(r) }
            match
          elsif replacement_path = @proc.call(asset_path, dirpath)
            "#{opening_character}#{replacement_path}"
          else
            match
          end
        end
      end
    end
  end
end
