# Example image data

The PNG / JPG files in this directory are sample images vendored from
the [notcurses](https://github.com/dankamongmen/notcurses) project
(Apache-2.0 licensed), used by `examples/viewported-card-list.raku`
to demonstrate `Selkie::Widget::Image` inside a `ViewportedCardList`.

Vendored verbatim — no transformations. Total ~1.2 MB. Selkie itself
ships no images and isn't an image-handling framework; these exist
purely so the example renders something interesting on a fresh
checkout without a sibling Notcurses-Native source tree.

Files:

| Filename          | Origin (notcurses `data/`)         |
|-------------------|------------------------------------|
| atma.png          | atma.png                           |
| chunli01.png      | chunli01.png                       |
| spaceship.png     | spaceship.png                      |
| eagles.png        | eagles.png                         |
| worldmap.png      | worldmap.png                       |
| natasha-blur.png  | natasha-blur.png                   |
| changes.jpg       | changes.jpg                        |
| notcurses.png     | notcurses.png                      |
| fonts.jpg         | fonts.jpg                          |
| aidsrobots.jpeg   | aidsrobots.jpeg                    |

To use your own images, set `SELKIE_DEMO_IMAGES=/path/a.png:/path/b.png`
when running the example.
