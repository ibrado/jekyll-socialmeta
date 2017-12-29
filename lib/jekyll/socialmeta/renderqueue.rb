module Jekyll
  module SocialMeta

    class RenderQueue
      def initialize(site)
        @prerendered = []
        @render_queue = {}
        @renamed = []

        Screenshot.setup(site, site.config['opengraph'])
      end

      def enqueue(screenshot)
        if screenshot.is_valid?
          @prerendered << screenshot

        else
          # For use with rewrite_to_local
          @render_queue[screenshot.source[:html]] = {
            :url => screenshot.source[:url],
            :base => screenshot.source[:base],
            :screenshot => screenshot
          }
        end
      end

      def render
        # Copy prerendered 
        @prerendered.each do |screenshot|
          SocialMeta::debug "Prerendered #{screenshot.source[:url]}"
          screenshot.activate 
        end

        # Rewrite relative paths
        rewrite_to_local(@render_queue)

        # Generate the screenshots
        @render_queue.each do |file, item|
          # Skip if e.g. it has an existing og:image
          url = item[:screenshot].source[:url]

          if item[:skip]
            SocialMeta::debug "Skipping #{url} (#{item[:skip]})"
          else
            SocialMeta::debug "Rendering #{url}"
            item[:screenshot].render
          end
        end

        @renamed.each do |file|
          File.rename("#{file.to_s}.jog-orig", file)
        end

      end

      def rewrite_to_local(queue)
        re = /(?:url\(|<(?:link|script|img)[^>]+(?:src|href)\s*=\s*)(?!['"]?(?:data|http|file))['"]?([^'"\)\s>]+)/i
        needs_rewrite = {}

        queue.each do |file, item|
          next if File.extname(file) !~ /\.x?html?/

          basedir = item[:base]
          content = File.read(file)

          # Check if the file already has a og:image
          if content =~ /<meta.*?property="og:image".*?content=['"].*?.*?['"]/
            item[:skip] = "existing og:image"
            next
          end

          content.scan(re).each do |local|
            relpath = local.first
            prefix = basedir + (relpath[0] == '/' ? '' : '/')

            abspath = prefix + relpath
            content.gsub!(/['"]#{relpath}['"]/, "file://#{abspath}")

            if abspath =~ /\.(css|html?)$/i
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
        @render_queue.length + @prerendered.length
      end
       
      def clear
        @renamed.clear
        @render_queue.clear
        @prerendered.clear
      end

      def finalize
        if @render_queue.length > 0
          Screenshot.save_all
          Screenshot.activate_all
          Screenshot.clean_all
        end
      end

    end
  end
end
