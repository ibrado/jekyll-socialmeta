require 'fastimage'

module Jekyll
  module SocialMeta
    WORK_DIR ='.jekyll-socialmeta'.freeze

    class Screenshot
      attr_reader :source, :urls, :sizes

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

        @@images_re = /\.(gif|jpe?g|png|tiff|bmp|ico|cur|psd|svg|webp)$/i
        @@images = {
          :og => "og-ts.jpg",
          :tcl => "tcl-ts.jpg",
          :tcs => "tcs-ts.jpg"
        }

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

        @@fallback_source = config['default'];
      end

      def self.save_all
        # Copy and rename
        @@instances.each do |screenshot|
          screenshot.copy_self(@@source_dir)
        end

      end

      def self.activate_all
        # Copy and possibly rename
        @@instances.each do |screenshot|
          screenshot.copy_self(@@dest_dir)
        end
      end

      def self.clean_all
        FileUtils.rm_r "#{@@temp_dir}"
      end

      def self.clear
        @@instances.clear
      end

      def initialize(item)
        @@instances << self

        config = @@config.merge(item.data['socialmeta'] || {})

        tw_config = config['twitter'] || config['twittercard'] || {}
        item_props = item.data['socialmeta'] || {}
        item_sm_image = item_props['image'] || {}
        @item_image = item.data['image']

        if !item_sm_image
          img = {}
        elsif item_sm_image.is_a?(Hash)
          img = item_sm_image
        else
          img = { 'source' => item_sm_image }
        end

        image_props = (@@config['image'] || {}).merge(img)
        @image = @@base_image.merge(image_props)

        # TODO: possibly override format/quality later
        @images = @@images.dup

        if tw_config['type'].nil? || tw_config['type'] == 'large'
          @images.delete(:tcs)
        else
          @images.delete(:tcl)
        end

        @urls = {}

        @source = {
          :url => item.url,
          :base => @@dest,
          :file => item.path,
          :html => item.destination('')
        }

        @default_source = item_sm_image['default'] || @@fallback_source
        # Setup temp folder
        # e.g. 2017-12-28-my-test
        @inner_path = File.join(File.basename(item.path, File.extname(item.path)))
        @base_url = "#{@@site_url}/#{@inner_path}/"

        # Create folders
        FileUtils.mkdir_p File.join(@@temp_dir, @inner_path)

        @temp_dir = File.join(@@temp_dir, @inner_path, '')
        @full_dir = File.join(@@source_dir, @inner_path, '')
        @live_dir = File.join(@@dest_dir, @inner_path, '')

        @item_dir = File.join(@@dest, Pathname(@item_image).dirname, '') if @item_image

        # Save timestamp if available and update URLs with it
        @timestamp = get_timestamp
        update_urls

        @page_snap = false

        src = (@image['source'] || "").strip
        if !src || (src =~ /^(screenshot|this|page)$/)
          SocialMeta::debug "Using screenshot as specified for "+item.url
          @page_snap = true
          source_url = 'file://' + @source[:html]

        elsif !src.empty?
          SocialMeta::debug "Using specified image for "+item.url
          source_url = preprocess_image(src)
          @page_snap = (source_url !~ @@images_re)

        elsif item.content =~ /!\[.*?\]\(|<img.*?src=['"]/
          SocialMeta::debug "Using largest image for "+item.url
          src = find_largest_image(item)
          source_url = preprocess_image(src)
        end

        if !source_url
          if @default_source != "none"
            SocialMeta::debug "Using screenshot as default for "+item.url
            @page_snap = true
            source_url = 'file://' + @source[:html]
          else
            SocialMeta::debug "No source URL for "+item.url
            return
          end
        end

        @source_url = source_url

        # Some styling

        if @image['center'] && !@page_snap
          @image['style'] = "margin-top: #{@image['centerTop']}px; margin-left: #{@image['centerLeft']}px; "+@image['style'].to_s
        end


        # Use instance vars so we can override as necessary
        @size = "#{@image['width']}x#{@image['height']}"
        @origin = "#{@image['top'].to_i},#{@image['left'].to_i}"
        @view_size = "#{@image['viewWidth'].to_i}x#{@image['viewHeight'].to_i}"
        @scroll = "#{@image['scrollTop'].to_i},#{@image['scrollLeft'].to_i}"
        @zoom = @image['zoom'].to_s
        @bg_style = item_props['style'].to_s
        @img_style = @image['style'].to_s

        update_params
      end

      def update_urls
        @images.each { |k,v|
          @urls[k] = timestamped(@base_url + v)
        }
      end

      def update_params
        width = @image['width'].to_i
        height = @image['height'].to_i

        @sizes = {
          :og => {
            :width => (width / 1.05).to_i,
            :height => height
          },
          :tcl => {
            :width => width,
            :height => height
          },
          :tcs => {
            :width => height,
            :height => height
          }
        }

        @params = @@base_params.map {
          |k,v| "--#{k}=#{v.to_s}"
        }

        # TODO: Maybe just use ENV for (most of) these?

        @params += [
          @@script,
          @source_url,
          @temp_dir,
          @origin,
          @size,
          @view_size,
          @scroll,
          @zoom,
          @bg_style,
          @img_style
        ]
      end

      def render
        if !@source_url
          SocialMeta::debug "Render skipped: no source URL"
          return false
        end

        pj_start = Time.now

        ENV['image_formats'] = @images.keys.join(',')
        ENV['page_snap'] = @page_snap ? '1' : '0'

        success = true
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

          else
            SocialMeta::debug "Phantomjs #{msg}"
          end
        }

        pj_runtime = "%.3f" % (Time.now - pj_start).to_f

        if success
          update_urls

          # Remove old images, replacements will be copied later
          FileUtils.rm_f(Dir.glob(File.join(@full_dir, '/*')));
          FileUtils.rm_f(Dir.glob(File.join(@live_dir, '/*')));

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

      def get_timestamp
        ts = '0000000000'
        @images.each { |k,v|
          image = File.join(@temp_dir, v)
          if File.exist? image
            ts = File.mtime(image).to_i.to_s
            break
          end
        }
        ts
      end

      private
      def adjust_image(image, size)
        actual_width = size.first.to_f
        actual_height = size.last.to_f

        top = image['top']
        left = image['left']
        zoom =  image['zoom']

        ratio = @@base_image['width'].to_i / @@base_image['height'].to_i
        ratio_width = actual_height * ratio
        ratio_height = actual_width / ratio

        # Facebook minimum height is 315
        if ratio_height >= 315
          top += (actual_height - ratio_height) / 2

          # Render height/width, for centering
          r_width = actual_width
          r_height = ratio_height

          width = actual_width
          height = ratio_height

          v_width = actual_width
          v_height = [actual_height, ratio_height].max

        else
          r_height = actual_height
          r_width = actual_width

          height = actual_height
          width = ratio_width

          v_height = actual_height
          v_width = [actual_width, ratio_width].max
        end

        center_top = 0
        center_left = 0

        if image['center']
          # Only one of these will actually take effect;
          #   the other will be 0 since either width or height will be kept
          center_top = (height - r_height) / 2
          center_left = (width - r_width) / 2
        end

        if image['resize']
          zoom *= @@base_image['width'] / width
          height *= zoom
          width *= zoom
          top *= zoom

          # The * 2 is to give the viewport "breathing space"
          #  so it doesn't distort the image
          v_height = [@@base_image['height'], actual_height].max * 2
          v_width = @@base_image['width']
        end

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
        if src && (src =~ @@images_re)
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
      def get_image_size(img, item)
        # Could be a match result
        src = (img[1] || img[0]).strip

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
          { :source => src,
            #:height => h,
            #:width => w,
            :area => w*h
          }
        else
          nil
        end
      end

      private
      def find_largest_image(item)

        src = ""
        src_sizes = []
        # Find all the non-referenced images

        image_tag_re = /!\[.*?\]\((.*?)\)|<img.*?src=['"](.*?)['"]/i
        item.content.scan(image_tag_re).each do |img|
          size = get_image_size(img, item)
          src_sizes << size if size
        end

        image_ref_re = /!\[(.*?)\][^\(]/
        item.content.scan(image_ref_re).each do |r|
          ref = r[0]
          if img = item.content.match(/\[#{ref}\]:\s+(\S+)/)
            size = get_image_size(img, item)
            src_sizes << size if size
          end
        end

        sorted = src_sizes.sort_by { |k| k[:area] };
        # Find largest by area
        largest = src_sizes.sort_by { |k| k[:area] }.last[:source]
        largest =~ /^\// ? "file://#{largest}" : largest

      end

      private
      def copy(src, dest)
        dest = File.join(dest, '')
        if @item_image && (dest == @live_dir)
          dest = @item_dir
        end

        # src and dest must be folders
        if !File.exist?(dest)
          FileUtils.mkdir_p dest
        end

        @images.each do |k,v|
          src_file = (src == @temp_dir ? v : timestamped(v))
          dest_file = item_image_name(dest) || timestamped(v)

          FileUtils.cp(File.join(src, src_file),
            File.join(dest, dest_file))
        end
      end

      private
      def item_image_name(dest)
        File.basename(@item_image) if @item_image && (dest == @item_dir)
      end

      private
      def timestamped(path)
        ts_re = /^(.*?)-ts(\.[^\.]+)$/
        path.gsub(ts_re, '\1-' + @timestamp  + '\2')
      end

    end

  end
end
