require 'jekyll/socialmeta/screenshot'

module Jekyll
  module SocialMeta

    class Tagger
      def initialize(site)
        @tag_queue = []

        @site = site
        @config = site.config['socialmeta'] || {}
        @site_desc = site.config['description'] || 'No description'
        @site_url = (site.config['canonical'] || site.config['url']) + site.config['baseurl']
      end

      def enqueue(item, screenshot)
        info = @config.merge(item.data['socialmeta'] || {})

        info[:title] = item.data['title'] || 'Untitled'
        info[:desc] = item.data['description'] || @site_desc
        info[:url] = @site_url + item.url
 
        @tag_queue << {
          :item => item,
          :info => info,
          :screenshot => screenshot
        }

      end

      def finalize
        @tag_queue.each do |qitem|
          info = qitem[:info]

          screenshot = qitem[:screenshot]
          file = screenshot.source[:html]

          # XXX
          info[:og] = screenshot.urls[:og]
          info[:tcl] = screenshot.urls[:tcl]
          info[:tcs] = screenshot.urls[:tcs]

          next if File.extname(file) !~ /\.x?html?/

          content = File.read(file)
          tags = metatags(info)

          content.gsub!(/(<head.*?>#{$/}*)/, '\1' + tags)

          File.write(file, content)
        end

        @tag_queue.clear

      end

      def opengraph(info)
        og_config = @config['opengraph'] || @config['facebook'] || {}
        type = og_config['type'] || 'website';

        %Q{<meta property="og:url" content="#{info[:url]}"/>\n} +
        %Q{<meta property="og:type" content="#{type}"/>\n} +
        %Q{<meta property="og:title" content="#{info[:title]}"/>\n} +
        %Q{<meta property="og:description" content="#{info[:desc]}"/>\n} +
        %Q{<meta property="og:image" content="#{info[:og]}"/>\n}
      end

      def twittercard(info)
        tc_config = @config['twittercard'] || @config['twitter'] || {}
        ""
      end

      def twittercard_large
      end

      def twittercard_summary
      end

      def metatags(info)
        tags = opengraph(info) + twittercard(info)
        indent = ' ' * (@config['indent'] || 0)
        tags.gsub!(/^/, indent)
      end

    end

  end
end

