# Gutter

A comic reader for iPad and iPhone that connects to your self-hosted
[Komga](https://komga.org) server. Built with Flutter.

- Reads CBZ/CBR/PDF comics from your server, with progress synced both ways
- Local-first library mirror, so the library and reading progress work offline
- Fit modes, two-page spreads, and guided spread/panel zoom

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
