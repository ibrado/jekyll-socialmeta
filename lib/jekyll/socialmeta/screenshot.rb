require 'fastimage'

module Jekyll
  module SocialMeta
    WORK_DIR ='.jekyll-socialmeta'.freeze

    class Screenshot
      attr_reader :source, :urls, :temp_path, :full_path, :live_path

      def self.setup(site, config)
        @@config = config || {}
        @@dest = site.dest
        @@source = site.source

        @@instances = []

        images_path = File.join(config['images'] || 'images', 'socialmeta')

        @@temp_dir = File.join(site.source, WORK_DIR, 'screenshots', images_path)
        @@source_dir = File.join(site.source, images_path)
        @@dest_dir = File.join(site.dest, images_path)

        @@cache_dir = File.join(site.source, WORK_DIR, 'cache')

        FileUtils.mkdir_p @@temp_dir
        FileUtils.mkdir_p @@source_dir

        # Doesn't work at this point if _site was erased
        # Jekyll resets it
        #FileUtils.mkdir_p @@dest_dir

        FileUtils.mkdir_p @@cache_dir

        pwd = Pathname.new(File.dirname(__FILE__))
        @@script = "#{pwd}/screenshot.js"

        site_url = site.config['url'] + site.config['baseurl']
        @@site_url = "#{site_url}#{images_path}"

        @@images = {
          :og => "og-ts.jpg",
          :tcl => "tcl-ts.jpg",
          :tcs => "tcs-ts.jpg"
        }

        @@base_params = {
          #'debug': true,
          #'proxy-type': 'none',
          'web-security': false,
          'ssl-protocol': 'tlsv1',
          #'ssl-protocol': 'any',
          'ignore-ssl-errors': true,
          'local-to-remote-url-access': true,
          'disk-cache': true,
          'disk-cache-path': @@cache_dir
        }.merge(config['phantomjs'] || {})

        @@base_image = {
          "resize" => true,
          "center" => false,
          "top" => 0,
          "left" => 0,
          "width" => 1260,
          "height" => 630,
          "viewWidth" => 1260,
          "viewHeight" => 630,
          "centerTop" => 0,
          "centerLeft" => 0,
          "scrollTop" => 0,
          "scrollLeft" => 0,
          "zoom" => 1
        }.merge(config['image'] || {})

        @@fallback_source = config['default'];
      end

      def self.save_all
        # Copy and rename
        @@instances.each do |screenshot|
          screenshot.copy_self(@@source_dir)
        end

      end

      def self.activate_all
        FileUtils.cp_r "#{@@source_dir}/.", "#{@@dest_dir}"
      end

      def self.clean_all
        FileUtils.rm_r "#{@@temp_dir}"
      end

      def self.clear
        @@instances.clear
      end

      def initialize(item)
        @@instances << self

        # For possible override of format later
        @images = @@images.dup
        @urls = {}

        @source = {
          :url => item.url,
          :base => @@dest,
          :file => item.path,
          :html => item.destination('')
        }

        # Setup temp folder
        # e.g. 2017-12-28-my-test
        @inner_path = File.join(File.basename(item.path, File.extname(item.path)))

        # Create folders
        FileUtils.mkdir_p File.join(@@temp_dir, @inner_path)
        FileUtils.mkdir_p File.join(@@source_dir, @inner_path)

        # Will insert timestamp later, necessary to prevent FB from caching unupdated ones

        # e.g. 2017-12-28-my-test/og-ts.png
        # XXX

        @temp_dir = File.join(@@temp_dir, @inner_path, '')
        @full_dir = File.join(@@source_dir, @inner_path, '')
        @live_dir = File.join(@@dest_dir, @inner_path, '')

        temp_path = File.join(@temp_dir, 'tcl-ts.jpg')

        # Save timestamp if available
        @timestamp = is_available? ?
          File.mtime(temp_path).to_i.to_s : '0000000000'

        @base_url = "#{@@site_url}/#{@inner_path}/"

        update_urls

        item_props = item.data['socialmeta'] || {}

        # TODO merge_hash
        item_image = item_props['image'] || {}
        @default_source = item_image['default'] || @@fallback_source

        if !item_image
          img = {}
        elsif item_image.is_a?(Hash)
          img = item_image
        else
          img = { 'source' => item_image }
        end

        image_props = (@@config['image'] || {}).merge(img)
        @image = @@base_image.merge(image_props)

        src = (@image['source'] || "").strip
        if !src || (src =~ /^(screenshot|this|page)$/)
          SocialMeta::debug "Using screenshot as specified for "+item.url
          source_url = 'file://' + @source[:html]

        elsif item.content =~ /!\[.*?\]\(|<img.*?src=['"]/
          SocialMeta::debug "Using largest image for "+item.url
          src = find_largest_image(item)
          source_url = preprocess_image(src)

        elsif !src.empty?
          SocialMeta::debug "Using specified image for "+item.url
          source_url = preprocess_image(src)
        end

        if !source_url
          if @default_source != "none"
            SocialMeta::debug "Using screenshot as default for "+item.url
            source_url = 'file://' + @source[:html]
          else
            SocialMeta::debug "No source URL for "+item.url
            return
          end
        end

        @source_url = source_url

        @params = @@base_params.map {
          |k,v| "--#{k}=#{v.to_s}"
        }

        # Some styling

        if @image['center']
          @image['style'] = "margin-top: #{@image['centerTop']}px; margin-left: #{@image['centerLeft']}px; "+@image['style'].to_s
        end

        origin = "#{@image['top'].to_i},#{@image['left'].to_i}"
        dim = "#{@image['width'].to_i}x#{@image['height'].to_i}"
        view_dim = "#{@image['viewWidth'].to_i}x#{@image['viewHeight'].to_i}"
        scroll = "#{@image['scrollTop'].to_i},#{@image['scrollLeft'].to_i}"

        @params += [
          @@script,
          source_url,
          @temp_dir,
          origin,
          dim,
          view_dim,
          scroll,
          @image['zoom'].to_s,
          item_props['style'].to_s,
          @image['style'].to_s
        ]
      end

      def update_urls
        @images.each { |k,v|
          @urls[k] = timestamped(@base_url + v)
        }
      end

      def render
        if !@source_url
          SocialMeta::debug "Render skipped: no source URL"
          return false
        end

        pj_start = Time.now

        success = true
        puts @params.inspect
        Phantomjs.run(*@params) { |msg|
          msg.strip!
          pj_info = msg.split(' ',2)

          if pj_info.first == 'error'
            SocialMeta::error "Phantomjs: #{pj_info[1]}"
            success = false
          elsif pj_info.first == 'debug'
            SocialMeta::debug "Phantomjs: #{pj_info[1]}"
          elsif pj_info.first == 'success'
            SocialMeta::debug "Phantomjs: Timestamp: #{pj_info[1]}"
            @timestamp = pj_info[1]
            puts "TIMESTAMP: "+@timestamp.inspect

          else
            SocialMeta::debug "Phantomjs #{msg}"
          end
        }

        pj_runtime = "%.3f" % (Time.now - pj_start).to_f

        if success
          update_urls

          # Remove old images, replacements will be copied later
          FileUtils.rm_f(File.join(@full_dir, '/*'));
          FileUtils.rm_f(File.join(@live_dir, '/*'));

          SocialMeta::debug "Phantomjs: #{@source[:url]} done in #{pj_runtime}s"
        end

        success
      end

      def activate
        if !is_saved?
          if is_available?
            copy(@temp_dir, @full_dir)
          else
            save
          end
        end

        copy(@full_dir, @live_dir)
      end

      def save
        if !is_available?
          render
        end

        copy(@temp_dir, @full_dir)
      end

      def is_available?
        available = true
        @images.each { |k,v|
          available &&= File.exist? File.join(@temp_dir, v)
        }
        available
      end

      def is_saved?
        saved = true
        @images.each { |k,v|
          saved &&= File.exist? File.join(@full_dir, timestamped(v))
        }
        saved
      end

      def is_live?
        live = true
        @images.each { |k,v|
          live &&= File.exist? File.join(@live_dir, timestamped(v))
        }
        live 
      end

      def is_rendered?
        is_saved? || is_available?
      end

      def exist?
        is_rendered?
      end

      def is_valid?
        source_older_than?(@full_dir) || source_older_than?(@temp_dir)
      end

      def is_expired?
        !valid?
      end

      def source_older_than?(image_dir)
        src_mtime = File.mtime(@source[:file])
        is_temp = (image_dir == @temp_dir)

        older = true
        @images.each do |k,v|
          image = File.join(image_dir, (is_temp ? v : timestamped(v)))
          older &&= File.exist?(image) && src_mtime < File.mtime(image)
        end
        older
      end

      def copy_self(dest_dir)
        copy(@temp_dir, File.join(dest_dir, @inner_path))
      end

      private
      def adjust_image(image, size)
        r_width = width = actual_width = size.first.to_f
        r_height = height = actual_height = size.last.to_f

        zoom = image['zoom']
        top = image['top']
        left = image['left']
        center_top = 0
        center_left = 0

        # The proportional height
        desired_ratio = 630 / 1260.0
        height = (width * desired_ratio).to_i

        # Expected height given the width and vice-versa
        expected_height = actual_width * desired_ratio
        expected_width = actual_height / desired_ratio

        # Crop from center
        if (actual_height < actual_width) && (height < actual_height)
          top += (actual_height - height) / 2
        end

        if image['resize']
          if actual_height > actual_width
            zoom *= (630.0 / actual_height)
            r_height = 630
            r_width = actual_width * zoom
          else
            zoom *= (1260.0 / actual_width)
            r_height = actual_height * zoom
            r_width = 1260
          end

          top *= zoom
          width *= zoom
          height *= zoom

          width = 1260
          height = 630

          v_width = 1260 * 2
          v_height = 630 * 2

        else
          r_width = width

          if actual_height < actual_width
            v_height = height * 2
            v_width = width * 2
            r_height = actual_height

          else
            r_height = height = actual_height
            width = expected_width
            v_height = height * 2
            v_width = width * 2
          end

        end

        center_left = ((width - r_width) / 2) / zoom
        center_top = (top + (height - r_height) / 2) / zoom

        image['top'] = top.to_i
        image['left'] = left.to_i
        image['width'] = width.to_i
        image['height'] = height.to_i
        image['centerTop'] = center_top.to_i
        image['centerLeft'] = center_left.to_i
        image['viewWidth'] = v_width.to_i
        image['viewHeight'] = v_height.to_i
        image['zoom'] = "%.8f" % zoom
      end

      private
      def preprocess_image(src)
        #((src !~ /^.*?:\/\//) || (src =~ /^file:\/\//) || )
        images_re = /\.(gif|jpe?g|png|tiff|bmp|ico|cur|psd|svg|webp)$/i
        if src && (src =~ images_re)
          # Local or remote image
          if m = /^file:\/\/(.+)/.match(src)
            source_img = m[1]
            source_url = src
          elsif src =~ /:\/\//
            source_img = src
            source_url = src
          else
            source_img = File.join(@@dest, src)
            source_url = 'file://' + source_img
          end

          # See what dimensions it has
          if size = FastImage.size(source_img)
            adjust_image(@image, size)
          else
            SocialMeta::warn "Unable to determine size of image"
            SocialMeta::warn " Check network connection, and URL for typos."
            source_url = nil
          end

        else
          source_url = src
        end

        source_url
      end

      private
      def find_largest_image(item)
        image_tag_re = /!\[.*?\]\((.*?)\)|<img.*?src=['"](.*?)['"]/i

        # Find all the images

        src = ""
        src_sizes = []

        item.content.scan(image_tag_re).each do |img|
          src = (img[0] || img[1]).strip

          if m = /^file:\/\/(.+)$/.match(src)
            src = m[1]

          elsif src !~ /:\/\//
            if src =~ /^\//
              src = File.join(@@dest, src.split('/'))
            else
              src = File.join(@@dest, item.url, src)
            end

          # else use remote source as-is
          end

          if size = FastImage.size(src)
            w = size.first
            h = size.last
            src_sizes << { :source => src,
              #:height => h,
              #:width => w,
              :area => w*h
            }
          end
        end

        # Find largest by area
        largest = src_sizes.sort_by { |k,v| v }.last[:source]
        largest =~ /^\// ? "file://#{largest}" : largest

      end

      private
      def copy(src, dest)
        puts "COPY ORIG SRC=#{src} DEST=#{dest}"
        # src and dest must be folders
        if !File.exist?(dest)
          FileUtils.mkdir_p dest
        end

        @images.each do |k,v|
          src_file = (src == @temp_dir ? v : timestamped(v))
          dest_file = timestamped(v)
          puts " --> COPYING #{File.join(src, src_file)} to #{File.join(dest, dest_file)}"
          FileUtils.cp(File.join(src, src_file), 
            File.join(dest, dest_file))
        end
      end

      private
      def timestamped(path)
        ts_re = /^(.*?)-ts(\.[^\.]+)$/
        path.gsub(ts_re, '\1-' + @timestamp  + '\2')
      end

    end

  end
end
