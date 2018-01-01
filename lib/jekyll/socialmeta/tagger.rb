require 'jekyll/socialmeta/screenshot'

module Jekyll
  module SocialMeta

    class Tagger
      def initialize(site)
        @tag_queue = []

        @site = site
        @config = site.config['socialmeta'] || {}
        @site_desc = site.config['description'] || 'No description'
        @site_url = site.config['url'] + site.config['baseurl']
      end

      def enqueue(item, screenshot)
        info = {
          :title => item.data['title'] || 'Untitled',
          :desc => item.data['description'] || @site_desc,
          :url => @site_url + item.url,
        }

        @tag_queue << {
          :config => item.data['socialmeta'] || {},
          :info => info,
          :screenshot => screenshot
        }

      end

      def finalize
        @tag_queue.each do |qitem|
          config = qitem[:config]
          info = qitem[:info]

          screenshot = qitem[:screenshot]
          info[:og] = screenshot.urls[:og]
          info[:tcl] = screenshot.urls[:tcl]
          info[:tcs] = screenshot.urls[:tcs]

          file = screenshot.source[:html]
          next if File.extname(file) !~ /\.x?html?/

          content = File.read(file)
          tags = metatags(config, info)

          content.gsub!(/(<head.*?>#{$/}*)/, '\1' + tags)

          File.write(file, content)
        end

        @tag_queue.clear

      end

      def opengraph(config, info)
        og_config = (config['opengraph'] || config['facebook'] || {}).
          merge(@config['opengraph'] || @config['facebook'] || {})

        type = og_config['type'] || 'website';

        %Q{<meta property="og:url" content="#{info[:url]}"/>\n} +
        %Q{<meta property="og:type" content="#{type}"/>\n} +
        %Q{<meta property="og:title" content="#{info[:title]}"/>\n} +
        %Q{<meta property="og:description" content="#{info[:desc]}"/>\n} +
        %Q{<meta property="og:image" content="#{info[:og]}"/>\n} +
        (og_config['fb_app_id'] ? %Q{<meta property="fb:app_id" content="#{og_config['fb_app_id']}"/>\n} : '')
      end

      def twittercard(config, info)
        tc_config = (config['twittercard'] || config['twitter'] || {}).
          merge(@config['twittercard'] || @config['twitter'] || {})

        creator = tc_config['creator'] || tc_config['handle'] || tc_config['creator']
        site = tc_config['site'] || tc_config['creator'] || tc_config['handle']

        if (tc_config['size'] || 'large') == 'large'
          type = 'summary_large_image'
          image = info[:tcl]
        else
          type = 'summary'
          image = info[:tcs]
        end

        if creator
          %Q{<meta name="twitter:card" content="#{type}"/>\n} +
          %Q{<meta name="twitter:site" content="#{site}"/>\n} +
          %Q{<meta name="twitter:creator" content="#{creator}"/>\n} +
          (tc_config['force'] ? %Q{<meta name="twitter:title" content="#{info[:title]}"/>\n} : '') +
          (tc_config['force'] ? %Q{<meta name="twitter:description" content="#{info[:desc]}"/>\n} : '') +
          %Q{<meta name="twitter:image" content="#{image}"/>\n} +
          (tc_config['alt'] ? %Q{<meta name="twitter:image:alt" content="#{tc_config['alt']}"/>\n} : '')

        else
          SocialMeta::warn "No Twitter Card creator specified -- no TC meta tags generated"
          ""
        end
      end

      def metatags(config, info)
        tags = twittercard(config, info) + opengraph(config, info)
        indent = ' ' * (@config['indent'] || 0)
        tags.gsub!(/^/, indent)
      end

    end

  end
end

