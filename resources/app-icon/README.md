# App icon

`gen.swift` draws the icon with Core Graphics, so there are no SVG sources to keep in step. Edit it and run
`swift gen.swift` in this folder; it rewrites the ten PNGs of `../Assets.xcassets/AppIcon.appiconset` and
`icon.png` (1024 px, used by the README).

The icon is a screen showing a strip of columns: the focused one in the middle with a ring, a stack of two
windows beside it, and the neighbours cut off by the screen's edges. It echoes the menu bar icon, which is drawn
in code by `Sources/AppBundle/ui/menubar/MenuBarLayoutIcon.swift`. The body is 824 px on the 1024 px macOS grid
with the same continuous corner curve as the minimap.

The 16 and 32 point slots (up to 64 px) use a simpler drawing: three wide columns, no title bars and no stacked
windows, so the shapes stay readable at that size.

Not yet done: an Icon Composer `.icon` for macOS 26 appearances.
