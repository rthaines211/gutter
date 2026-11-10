# Gutter

A comic reader for iPad and iPhone for self-hosted comic libraries. Built with
Flutter. An Android build is in preparation.

[Gutter on the App Store](https://apps.apple.com/us/app/gutter-comic-reader/id6831270255)

- Connects to [Komga](https://komga.org), [Kavita](https://www.kavitareader.com)
  (0.9+) or the [Gutter server](https://github.com/rthaines211/gutter-server),
  with two-way progress sync
- Local-first library mirror, so the library and reading progress work offline
- Fit modes, page or vertical scroll, left-to-right or right-to-left
- Gutter Pro (one-time purchase): offline downloads, guided zoom panel by
  panel and through two-page spreads, more than one server, reading stats.
  Panels are found on the device, so guided zoom works with Komga and Kavita

## Build

```sh
flutter pub get
flutter run
```

Personal build settings (device IDs, a default server) can go in an untracked
`Makefile.local`; see the top of `Makefile`.

## License

Source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE).
You may read, modify and run it for noncommercial purposes. Commercial use,
including publishing builds to an app store, is reserved to the copyright holder.
Third-party assets are not covered by that license; see [NOTICE](NOTICE).
