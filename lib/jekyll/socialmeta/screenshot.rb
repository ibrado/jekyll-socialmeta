require 'fastimage'

module Jekyll
  module SocialMeta
    WORK_DIR ='.jekyll-socialmeta'.freeze

    class Screenshot
      attr_reader :source, :url, :temp_path, :full_path, :live_path

      def self.setup(site, config)
        @@config = config || {}
        @@dest = site.dest
        @@source = site.source

        if config['images']
          image_path_prefix = File.join(config['images'])
        else
          image_path_prefix = File.join('assets', 'images')
        end

        images_path = File.join(image_path_prefix, 'socialmeta')

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
        @@site_url = "#{site_url}/#{images_path}"

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
          "enlarge" => true,
          "top" => 0,
          "left" => 0,
          "width" => 1200,
          "height" => 630,
          "viewWidth" => 1200,
          "viewHeight" => 630,
          "scrollTop" => 0,
          "scrollLeft" => 0,
          "zoom" => 1
        }.merge(config['crop'] || {})

      end

      def self.save_all
        FileUtils.cp_r "#{@@temp_dir}/.", "#{@@source_dir}"
      end

      def self.activate_all
        FileUtils.cp_r "#{@@source_dir}/.", "#{@@dest_dir}"
      end

      def self.clean_all
        FileUtils.rm_r "#{@@temp_dir}"
      end

      def initialize(item)
        @source = {
          :url => item.url,
          :base => @@dest,
          :file => item.path,
          :html => item.destination('')
        }

        @name = 'og-image.jpg' # XXX

        # Setup temp folder
        # e.g. 2017-12-28-my-test
        inner_path = File.join(File.basename(item.path, File.extname(item.path)))

        # Create folders
        FileUtils.mkdir_p File.join(@@temp_dir, inner_path)
        FileUtils.mkdir_p File.join(@@source_dir, inner_path)

        # e.g. 2017-12-28-my-test/og-image.png
        @path = File.join(inner_path, @name)

        @temp_path = File.join(@@temp_dir, @path)
        @full_path = File.join(@@source_dir, @path)
        @live_path = File.join(@@dest_dir, @path)

        @url = "#{@@site_url}/#{inner_path}/#{@name}"

        item_props = item.data['socialmeta'] || {}

        # TODO merge_hash
        item_image = item_props['image']
        puts
        puts "ITEM_IMAGE: #{item_image.inspect}"

        if !item_image
          img = {}
        elsif item_image.is_a?(Hash)
          img = item_image
        else
          img = { 'source' => item_image }
        end

        puts
        puts "IMG: #{img.inspect}"

        image_props = (@@config['image'] || {}).merge(img)

        puts
        puts "IMAGE PROPS: #{image_props.inspect}"

        @image = @@base_image.merge(image_props)
        puts
        puts "ORIG IMAGE: #{@image.inspect}"

        if src = @image['source']
          source_url = preprocess_image(src)

        elsif item.content =~ /!\[.*?\]\(|<img.*?src=['"]/
          src = find_largest_image(item)
          source_url = preprocess_image(src)

        else
          source_url = 'file://' + @source[:html]
        end

        puts
        puts "AFTER IMAGE: #{@image.inspect}"

        # TODO build_params so screenshot can be adjusted before rendering
        #      Need to expose source, w, h, vw, vh, top, left, scroll
        @params = @@base_params.map {
          |k,v| "--#{k}=#{v.to_s}"
        }

        # Work around scrollPosition bug
        zoom = @image['zoom'].to_f

        scroll_top = @image['scrollTop'].to_i
        @image['top'] += scroll_top
        @image['viewHeight'] += scroll_top

        scroll_left = @image['scrollLeft'].to_i
        @image['left'] += scroll_left
        @image['viewWidth'] += scroll_left

        #@image['style'] += " margin-left: #{(-scroll_left * zoom).to_i}px"
        #@image['viewWidth'] += scroll_left * zoom

        # Some styling
        #item_props['style'] = 'background-color: white; ' + item_props['style'].to_s
        if @image['center']
          item_props['style'] = 'text-align: center; ' + item_props['style'].to_s
          @image['style'] = 'margin: auto; '+@image['style'].to_s
        end


        puts
        puts "FINAL IMAGE: #{@image.inspect}"

        origin = "#{@image['top'].to_i},#{@image['left'].to_i}"
        dim = "#{@image['width'].to_i}x#{@image['height'].to_i}"
        view_dim = "#{@image['viewWidth'].to_i}x#{@image['viewHeight'].to_i}"
        scroll = "#{@image['scrollTop'].to_i},#{@image['scrollLeft'].to_i}"

        @params += [
          @@script,
          source_url,
          @temp_path,
          origin,
          dim,
          view_dim,
          scroll,
          @image['zoom'].to_s,
          item_props['style'].to_s,
          @image['style'].to_s
        ]
      end

      def render
        pj_start = Time.now

        puts @params.inspect
        ENV['hello'] = 'world'
        ENV['site_base'] = 'file://'+@@source+'/'
        puts "SITE BASE: #{ENV['site_base']}"

        error = false
        Phantomjs.run(*@params) { |msg|
          pj_info = msg.split(' ',2)

          if pj_info.first == 'error'
            SocialMeta::error "Phantomjs: #{pj_info[1]}"
            error = true
          elsif pj_info.first == 'debug'
            SocialMeta::debug "Phantomjs: #{pj_info[1]}"
          else
            SocialMeta::debug "Phantomjs #{msg}"
          end
        }

        pj_runtime = "%.3f" % (Time.now - pj_start).to_f
        if !error
          SocialMeta::debug "Phantomjs: #{@source[:url]} done in #{pj_runtime}s"
        end

        error
      end

      def activate
        if !is_saved?
          if is_available?
            copy(@temp_path, @full_path)
          else
            save
          end
        end

        copy(@full_path, @live_path)
      end

      def save
        if !is_available?
          render
        end

        copy(@temp_path, @full_path)
      end

      def is_available?
        File.exist? @temp_path
      end

      def is_saved?
        File.exist? @full_path
      end

      def is_live?
        File.exist? @live_path
      end

      def is_rendered?
        is_saved? || is_available?
      end

      def exist?
        is_rendered?
      end

      def is_valid?
        (is_saved? && (File.mtime(@source[:file]) <= File.mtime(@full_path))) ||
          (is_available? && (File.mtime(@source[:file]) <= File.mtime(@temp_path)))
      end

      def is_expired?
        !valid?
      end

      def adjust_image(image, size)
        width = actual_width = size.first.to_f
        height = actual_height = size.last.to_f

        zoom = image['zoom']
        top = image['top']
        left = image['left']

        puts "*** ORIG TOP: #{top}"

        # The proportional height
        height = (width * ( 630 / 1200.0)).to_i

        # Crop from center
        if height < actual_height
          top += (actual_height - height) / 2
        elsif height > 630
          top += (height - 630) / 2
        end

          # Adjust to proper proportions
        if image['enlarge']
          # Calculate zoom, format for consistent output with non-enlarged (rounding)
          zoom *= (1200.0 / actual_width)
          width = 1200
          height *= zoom

          top *= zoom
          #left = (1200 - width) / 2
          puts "*** ZOOM TOP: #{top}"

          puts "***  HEIGHT: #{height.to_i} WIDTH: #{width.to_i} TOP: #{top}"

          width = 1200
          height = 630
          v_width = 1200 * 2
          v_height = 630 * 2
          #v_width *= zoom
          #v_height *= zoom

        else

          v_height = height * 2
          v_width = width * 2

        end

        puts
        puts "***  ZOOM: #{zoom}"
        puts "***    AW: #{actual_width.to_i} AH: #{actual_height.to_i}"
        puts "*** NEW W: #{width.to_i} NH: #{height.to_i}"
        puts "***    VW: #{v_width.to_i} VH: #{v_height.to_i}"
        puts "***   TOP: #{top.to_i}"
        puts


        image['top'] = top.to_i
        image['left'] = left.to_i
        image['width'] = width.to_i
        image['height'] = height.to_i
        image['viewWidth'] = v_width.to_i
        image['viewHeight'] = v_height.to_i
        image['zoom'] = "%.8f" % zoom
        
      end


      def adjust_imagex(image, size)
        v_width = actual_width = size.first.to_f
        v_height = actual_height = size.last.to_f

        top = image['top']
        left = image['left']
        zoom = image['zoom']

        # XXX
        # TODO Declare constants or some class vars (for other sizes, e.g. Twitter Cards)

        # TODO Simplify these

        desired_ratio = 630 / 1200.0
        expected_height = actual_width * desired_ratio
        expected_width  = actual_height / desired_ratio

        #if actual_width < 1200 && actual_height > 630
        # TODO Allow user to select method
        if !image['fill']
          if actual_height > actual_width
            # Tall
            if actual_height < expected_height
              puts "IN 1 - Tall, no fill"
              # Tall image, center
              height_ratio = 630.0 / actual_height
              zoom *= height_ratio
              v_height = 630 * 2
            else
              # Really tall
              puts "IN 2 - Really tall, no fill"
              height_ratio = 630.0 / actual_height
              zoom *= height_ratio
              v_height = 630 / zoom
            end
            v_width = 1200 / zoom

          else
            puts "IN 3 - Wide, no fill"
            # Wide
            zoom *= (1200.0 / actual_width)

            margin = "#{((630 - (actual_height * zoom)) / 2).to_i}"
            image['style'] += " margin-top: #{margin};  margin-bottom: #{margin};"
            v_width = 1200 / zoom

          end
        else
          if actual_height > actual_width
            puts "IN 5 - Tall, fill"
            ratio = 1200.0 / actual_width
            zoom *= ratio
            top = (630 - expected_height) / zoom
            v_width = 1200 * 2
            
            if expected_height < 630
              puts "Using vheight 630*2"
              v_height = 630 * 2
            else
              puts "Using vheight 630/zoom"
              v_height = 630 / zoom
            end

          else
            puts "IN 6 - Wide, fill"

            desired_height = (630 / 1200.0) * actual_width
            top = (actual_height - desired_height) / 2
            zoom *= (1200.0 / actual_width)
            v_height = 630 * 2
            v_width = 1200 * 2
          end

          image['center'] = false;
        end

        # The viewport should be bigger so the image isn't resized by the "browser"
        #v_width = (width * zoom) + 100
        #v_height = (height * zoom) + 100

        image['top'] = (top * zoom).to_i
        image['left'] = (left * zoom).to_i
        #image['width'] = (width * zoom).to_i
        #image['height'] = (height * zoom).to_i
        image['width'] = 1200
        image['height'] = 630
        image['viewWidth'] = (v_width * zoom).to_i # XXX
        image['viewHeight'] = (v_height * zoom).to_i
        image['zoom'] = "%.8f" % zoom
      end

      def preprocess_image(src)
        #((src !~ /^.*?:\/\//) || (src =~ /^file:\/\//) || )
        images_re = /\.(gif|jpe?g|png|tiff|bmp|ico|cur|psd|svg|webp)$/i
        if src && (src =~ images_re)
          # Local or remote image
          puts "SRC: #{src}"
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

          puts "SOURCE IMAGE: #{source_img} SOURCE_URL: #{source_url}"
          # See what dimensions it has
          size = FastImage.size(source_img)
          puts "FASTIMAGE SIZE: #{size.inspect}"
          if size
            adjust_image(@image, size)
          else
            SocialMeta::warn "Unable to determine size, results not optimized"
          end

          puts "NEW IMAGE #{@image.inspect}"
          #puts "SIZE: #{size.inspect}"
        else
          source_url = src
        end

        source_url
      end

      def find_largest_image(item)
        image_tag_re = /!\[.*?\]\((.*?)\)|<img.*?src=['"](.*?)['"]/i

        # Find all local images

        src = ""

        item.content.scan(image_tag_re).each do |img|
          puts "IMG: #{img.inspect}"
          src = (img[0] || img[1]).strip
          puts "SAW IMAGE SRC #{src}"

          if m = /^file:\/\/(.+)$/.match(src)
            src = m[1]
          elsif src =~ /:\/\//
            # Ignore remote images
            next
          else
            if src =~ /^\//
              print "FULL PATH #{src}"
              src = File.join(@@dest, src.split('/'))
              puts " SRC=#{src}"
            else
              src = File.join(@@dest, item.url, src)
              puts "ITEM URL: #{item.url} SRC=#{src}"
            end
          end
        end

        "file://#{src}"

      end

      private
      def copy(src, dest)
        dest_path = Pathname(dest).dirname
        if !File.exist?(dest_path)
          FileUtils.mkdir_p dest_path
        end
        FileUtils.cp(src, dest)
      end

    end

  end
end
