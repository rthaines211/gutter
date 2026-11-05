# Gutter

A comic reader for iPad and iPhone for self-hosted comic libraries. Built with
Flutter.

- Connects to the [Gutter server](https://github.com/rthaines211/gutter-server)
  for the full feature set, or to Komga, Kavita and other OPDS servers to
  browse and read (OPDS is read-only, so progress stays on the device)
- Local-first library mirror, so the library and reading progress work offline
- Fit modes, two-page spreads, and guided spread zoom; guided panel zoom
  currently needs the Gutter server

A native Komga adapter with two-way progress sync is in progress.

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
