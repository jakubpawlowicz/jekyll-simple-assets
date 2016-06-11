require 'fileutils'

$assets = {}

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

      digested_url = url.sub(/\.\w+$/) { |match| "-#{digest(absolute_path)}#{match}" }
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

  def digest(absolute_path)
    content = File.open(absolute_path).read

    md5 = Digest::MD5.new
    md5 << content
    md5.hexdigest
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

Liquid::Template.register_tag('asset_url', AssetUrlTag)
Liquid::Template.register_tag('asset_inline', AssetInlineTag)

Jekyll::Hooks.register(:site, :post_write) do |jekyll|
  $assets.each do |source, target|
    source_path = jekyll.in_dest_dir(source)
    target_path = jekyll.in_dest_dir(target)

    if source =~ /\.js$/
      %x(uglifyjs --compress --mangle --output #{target_path} #{source_path})
    elsif source =~ /\.css$/
      %x(cleancss --output #{target_path} #{source_path})
    else
      FileUtils.mv(source_path, target_path)
    end
  end
end

Jekyll::Hooks.register(:site, :post_write) do |jekyll|
  next unless ENV.fetch('JEKYLL_ENV', '') == 'production'

  Dir.glob(File.join(jekyll.dest, '**/*.html')).each do |filename|
    File.open(filename, 'r+') do |file|
      source = file.read.force_encoding('utf-8')
      processed = source.gsub(/<!-- inline (script|style):(\S+) -->\n/) do
        type = Regexp.last_match[1]
        asset_url = Regexp.last_match[2]
        asset_source = File.read(File.join(jekyll.dest, asset_url))

        "<#{ type }>#{ asset_source }</#{ type }>\n"
      end

      file.rewind
      file.truncate(0)
      file.write(processed)
    end
  end
end
