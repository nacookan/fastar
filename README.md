# fastar

Star-rate large image sets, fast.

It opens a folder of JPG and PNG images, shows a fast thumbnail strip, lets you inspect images with zoom and pan controls, assign 0-5 star ratings, filter/sort the current list, export filtered images, and compare images side by side.

## Build

Open `fastar.xcodeproj` in Xcode, select the `fastar` scheme, and build/run the app.

The app targets macOS 14 or later.

## Regenerate App Icon

Run this command from the repository root:

```sh
swift scripts/generate_icon.swift
```

This regenerates the PNG files in `fastar/Resources/Assets.xcassets/AppIcon.appiconset`.
