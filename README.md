# jekyll-simple-assets

It's a simple Jekyll plugin for building production-ready assets. It **does not** support asset
bundling as in HTTP/2 world it's considered a __bad practice__.

## How to install it?

Copy assets.rb into your _plugins folder. Then make sure `uglifyjs` and `cleancss` binaries are
in $PATH, or customize assets.rb to use JS and CSS optimization tools of your choice.

**Note**: if you end up customizing assets.rb it's a __good practice__ to fork this repository and
put your edited assets.rb there so you can track changes.

## How to use it inside HTML?

```html
<link rel="stylesheet" href="{% asset_url /path/to/my.css %}">
<script src="{% asset_url /path/to/my.js %}"></script>
```

## How to use it inside CSS?

Prepend your CSS file with YAML comment so it's not considered static (anyone knows how to
work around this step?), then use `asset_url` helper as normal:

```css
---
---
...
.error {
  background-image: url({% asset_url /img/error.png %});
}
```

## How to inline assets inside HTML?

Well, server push is still not widely supported (as of June 2016), so here's how:

```html
{% asset_inline /path/to/my.css %}
```

## Why it's not published as a gem?

Because I'm lazy and it would make customizations harder.

## Why doesn't it support feature X?

Pull requests are welcome!

## License

jekyll-simple-assets is released under the [MIT License](https://github.com/jakubpawlowicz/jekyll-simple-assets/blob/master/LICENSE).
