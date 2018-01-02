require 'jekyll/socialmeta/screenshot'

module Jekyll
  module SocialMeta

    class Tagger
      def initialize(site)
        @tag_queue = []

        @site = site
        @site_name = site.config['name']
        @config = site.config['socialmeta'] || {}
        @site_desc = site.config['description'] || 'No description'
        @site_url = (site.config['canonical'] || site.config['url']) + site.config['baseurl']
      end

      def enqueue(item, screenshot)
        mtime = File.mtime(screenshot.source[:file]).to_datetime.to_s
        tags = [ item.data['tag'], item.data['tags'] ].flatten.compact.uniq
        cats = [ item.data['category'], item.data['categories'] ].flatten.compact.uniq

        info = {
          :title => item.data['title'] || 'Untitled',
          :desc => item.data['description'] || @site_desc,
          :url => @site_url + item.url,
          :data => item.data || {},
          'published' => item.data['date'] ? item.data['date'].to_datetime.to_s : mtime,
          'modified' => mtime,
        }

        @tag_queue << {
          :config => item.data['socialmeta'] || {},
          :info => info,
          :screenshot => screenshot,
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
          info[:sizes] = screenshot.sizes
          info[:source] = screenshot.source[:file]

          info[:alt] = (config['image'] || {})['alt']

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
        og_config = (@config['opengraph'] || @config['facebook'] || {}).
          merge(config['opengraph'] || config['facebook'] || {})

        type = og_config['type'] || 'website'
        site_name = og_config['site_name'] || @site_name

        tags = (site_name ? %Q{<meta property="og:site_name" content="#{site_name}"/>\n} : '' ) +
          %Q{<meta property="og:url" content="#{info[:url]}"/>\n} +
          %Q{<meta property="og:type" content="#{type}"/>\n} +
          %Q{<meta property="og:title" content="#{info[:title]}"/>\n} +
          %Q{<meta property="og:description" content="#{info[:desc]}"/>\n} +
          %Q{<meta property="og:image" content="#{info[:og]}"/>\n} +
          %Q{<meta property="og:image:width" content="#{info[:sizes][:og][:width]}"/>\n} +
          %Q{<meta property="og:image:height" content="#{info[:sizes][:og][:height]}"/>\n}

        tags += %Q{<meta property="og:image:alt" content="#{info[:alt]}"/>\n} if info[:alt]


        # All others
        og_config.each do |k,v|
          if k !~ /^(type|title|description|image|url|site_name)\b/
            props = get_properties(info, k, v)
            puts "GOT PROPS #{props.inspect}"

            # Support arrayes and hashes
            props.each { |p|
              p.each { |k1, v1|
                k1 = 'og:' + k1 if k1 !~ /:/
                [ v1 ].flatten.each { |v2|
                  tags += %Q{<meta property="#{k1}" content="#{v2}"/>\n} if v2
                }
              }
            }
          end
        end

        tags

      end

      def twittercard(config, info)
        tc_config = (@config['twittercard'] || @config['twitter'] || {}).
          merge(config['twittercard'] || config['twitter'] || {})

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

      private
      def get_properties(info, k, v)
        vals = []

        if v.is_a?(String)
          if m = /\$\.(\S*?)\[?(\d*)\]?$/.match(v)
            v = info[m[1]] || info[:data][m[1]]
            i = m[2]
            puts "SAW m[1]=#{m[1]} v=#{v} i=#{i}"

            if !i.empty? && (v.is_a?(Array))
              v = v[i.to_i]
              puts "SET V TO #{v} i=#{i} info[#{m[1]}]"
            end
          end
          vals << { k => v }

        elsif v.is_a?(Hash)
          v.each { |k1, v1|
            puts
            puts ">>> GETTING VALUE FOR #{k+':'+k1}: #{v1.inspect}"
            vals << get_properties(info, k+':'+k1, v1)
          }
        end

        puts "RETURN VALS: #{vals.flatten.inspect}"
        vals.flatten

      end

    end

  end
end

