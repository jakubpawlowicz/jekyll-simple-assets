# Version 1.0.0

require 'fileutils'

$assets = {}

class Stamp
  def self.file(absolute_path)
    content = File.open(absolute_path).read

    md5 = Digest::MD5.new
    md5 << content
    md5.hexdigest
  end
end

class DigestedFile < Jekyll::StaticFile
  def write(dest)
    # noop
  end
end

class GenericAssetTag < Liquid::Tag
  def initialize(tag_name, url, tokens)
    super
    @url = url.strip
  end

  def render(context)
    if production?
      site = context.registers[:site]
      page = context.registers.fetch(:page, {})
      absolute_path = File.join(site.source, url)

      digested_url = url.sub(/\.\w+$/) { |match| "-#{Stamp.file(absolute_path)}#{match}" }
      add_dependency(site, page, digested_url)
      mark_as_digested_asset(site, digested_url)

      render_in_production(digested_url)
    else
      render_in_development
    end
  end

  protected

  def render_in_development
    fail NotImplementedError
  end

  def render_in_production(digested_url)
    fail NotImplementedError
  end

  private

  attr_reader :url

  def production?
    ENV.fetch('JEKYLL_ENV', '') == 'production'
  end

  def add_dependency(site, page, digested_url)
    return unless page.key?('path')

    site.regenerator.add_dependency(
      site.in_source_dir(page['path']),
      site.in_source_dir(digested_url)
    )
  end

  def mark_as_digested_asset(site, digested_url)
    target_path = site.in_dest_dir(digested_url)
    target_dirname = File.dirname(target_path)
    target_basename = File.basename(target_path)
    asset_file = DigestedFile.new(site, site.source, target_dirname, target_basename)

    site.static_files << asset_file
    $assets[url] = digested_url
  end
end

class AssetUrlTag < GenericAssetTag
  def render_in_development
    url
  end

  def render_in_production(digested_url)
    digested_url
  end
end

class AssetInlineTag < GenericAssetTag
  def initialize(tag_name, url, tokens)
    super
    @type = url =~ /\.js$/ ? 'script' : 'style'
  end

  def render_in_development
    if type == 'script'
      %{<script src="#{ url }"></script>}
    else
      %{<link rel="stylesheet" href="#{ url }"/>}
    end
  end

  def render_in_production(digested_url)
    "<!-- inline #{ type }:#{ digested_url } -->"
  end

  private

  attr_reader :type
end

class Stylesheet
  def initialize(jekyll, target)
    @jekyll = jekyll
    @stylesheet_path = jekyll.in_dest_dir(target)

    @rewritten = nil
    @image_urls = []
  end

  def rewrite_urls
    @rewritten =
      File.read(stylesheet_path)
        .gsub(URL_PATTERN) {
          quote_left = $1
          source_url = $2
          quote_right = $3

          extension = File.extname(source_url)
          source_path = File.absolute_path(source_url, File.dirname(stylesheet_path))
          stamp = Stamp.file(source_path)
          digested_url = source_url.sub(extension, '-' + stamp + extension)
          digested_path = source_path.sub(extension, '-' + stamp + extension)

          image_urls << [source_path, digested_path]

          "url(#{quote_left}#{digested_url}#{quote_right})"
        }

    self
  end

  def copy_to_target
    File.open(stylesheet_path, 'w').write(rewritten)

    self
  end

  def copy_images_to_target
    image_urls.each { |source_path, target_path|
      Jekyll.logger.debug('image asset:', "'#{ source_path }' => '#{ target_path }'")

      FileUtils.cp(source_path, target_path)
    }

    self
  end

  private

  attr_reader :image_urls, :jekyll, :rewritten, :stylesheet_path

  URL_PATTERN = /url\((["']?)([^)]+)(["']?)\)/m
end

Liquid::Template.register_tag('asset_url', AssetUrlTag)
Liquid::Template.register_tag('asset_inline', AssetInlineTag)

Jekyll::Hooks.register(:site, :post_write) do |jekyll|
  next unless ENV.fetch('JEKYLL_ENV', '') == 'production'

  $assets.each do |source, target|
    source_path = jekyll.in_dest_dir(source)
    target_path = jekyll.in_dest_dir(target)

    if source =~ /\.js$/
      Jekyll.logger.debug('JS asset:', "'#{ source_path }' => '#{ target_path }'")
      %x(uglifyjs --compress --mangle --output #{target_path} #{source_path})
    elsif source =~ /\.css$/
      Jekyll.logger.debug('CSS asset:', "'#{ source_path }' => '#{ target_path }'")
      %x(cleancss --output #{target_path} #{source_path})
    else
      Jekyll.logger.warn('skipping:', "unknown asset type at #{ source_path }!")
    end
  end

  Jekyll.logger.info('Optimizing assets:', 'done!')
end

Jekyll::Hooks.register(:site, :post_write) do |jekyll|
  next unless ENV.fetch('JEKYLL_ENV', '') == 'production'

  $assets.each do |source, target|
    next unless source =~ /\.css$/

    Stylesheet.new(jekyll, target)
      .rewrite_urls
      .copy_to_target
      .copy_images_to_target
  end

  Jekyll.logger.info('Processing images:', 'done!')
end

Jekyll::Hooks.register(:site, :post_write) do |jekyll|
  next unless ENV.fetch('JEKYLL_ENV', '') == 'production'

  Dir.glob(File.join(jekyll.dest, '**/*.html')).each do |filename|
    Jekyll.logger.debug('HTML file:', "'#{ File.absolute_path(filename) }'")

    File.open(filename, 'r+') do |file|
      source = file.read.force_encoding('utf-8')
      processed = source.gsub(/<!-- inline (script|style):(\S+) -->\n/) do
        type = Regexp.last_match[1]
        asset_url = Regexp.last_match[2]
        asset_path = File.join(jekyll.dest, asset_url)
        asset_source = File.read(asset_path)

        Jekyll.logger.debug('', "embedding '#{ asset_path }'")

        "<#{ type }>#{ asset_source }</#{ type }>\n"
      end

      file.rewind
      file.truncate(0)
      file.write(processed)
    end
  end

  Jekyll.logger.info('Embedding assets:', 'done!')
end
