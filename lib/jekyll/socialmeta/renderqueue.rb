require 'jekyll/socialmeta/screenshot'

module Jekyll
  module SocialMeta

    class RenderQueue
      attr_accessor :errors, :cached

      def initialize(site)
        @cached = 0
        @render_queue = {}
        @renamed = []

        Screenshot.setup(site, site.config['socialmeta'])
      end

      def enqueue(screenshot)
        @render_queue[screenshot.source[:html]] = {
          :url => screenshot.source[:url],
          :base => screenshot.source[:base],
          :screenshot => screenshot
        }
      end

      def render
        # Generate the screenshots
        errors = 0

        @render_queue.each do |file, qitem|
          screenshot = qitem[:screenshot]

          # Skip if e.g. it has an existing og:image
          url = screenshot.source[:url]
          file = screenshot.source[:html]

          if screenshot.is_valid?
            @cached += 1
            screenshot.activate
            SocialMeta::debug "Skipping #{url} (cached)"
          else
            SocialMeta::debug "Rendering #{url}"
            # Rewrite relative paths
            rewrite_to_local(file => qitem)
            # Render image
            errors += 1 if !screenshot.render
          end

        end

        @errors = errors

        @renamed.each do |file|
          File.rename("#{file.to_s}.jog-orig", file)
        end

      end

      def rewrite_to_local(queue)
        re = /(?:url\(|<(?:link|script|img)[^>]+(?:src|href)\s*=\s*)(?!['"]?(?:data|http|file))['"]?([^'"\)\s>]+)/i
        needs_rewrite = {}

        queue.each do |file, qitem|
          next if File.extname(file) !~ /\.(x?html?|css)/

          basedir = qitem[:base]
          content = File.read(file)

          # Check if the file already has a og:image hardcoded
          #if content =~ /<meta.*?property="og:image".*?content=['"].*?.*?['"]/
          #  item[:skip] = "existing og:image"
          #  next
          #end

          content.scan(re).each do |local|
            relpath = local.first
            prefix = basedir + (relpath[0] == '/' ? '' : '/')

            abspath = prefix + relpath
            content.gsub!(/(['"\(])#{relpath}([\)'"])/, '\1'+"file://#{abspath}"+'\2')

            if abspath =~ /\.(css|x?html?)$/i
              ref_orig = Pathname.new(abspath + '.jog-orig')
              if !ref_orig.exist?
                ref_file = Pathname.new(abspath)
                needs_rewrite[abspath] =  { :base => ref_file.dirname.to_s }
              end
            end
          end

          File.rename(file, "#{file.to_s}.jog-orig")
          File.write(file, content)
          @renamed.push(file)

        end

        if !needs_rewrite.empty?
          rewrite_to_local(needs_rewrite)
        end
      end

      def length
        @render_queue.length
      end

      def jobs
        length - @cached
      end

      def clear
        @renamed.clear
        @render_queue.clear
        @cached = 0
        Screenshot.clear
      end

      def finalize
        if length > 0
          Screenshot.save_all
          Screenshot.activate_all
          #Screenshot.clean_all
        end
      end

    end
  end
end
