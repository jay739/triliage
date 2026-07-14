# Contributing to triliage

Thanks for considering a contribution. Issues, discussions and PRs are all
welcome.

## Getting set up

```
git clone https://github.com/jay739/triliage && cd triliage
flutter pub get
flutter run -d windows
```

Needs the Flutter SDK on the **beta channel** (stable does not yet support
the VS 2026 CMake generator on Windows) and VS Build Tools with the Desktop
C++ workload.

## Running the checks

```
flutter analyze
flutter test
```

## Ground rules

- Open an issue or discussion before large changes, so effort isn't wasted.
- Keep PRs focused: one change per PR.
- New behavior needs a test where the repo has a test suite.
- CI must pass before merge.

## Licensing

By contributing you agree your contributions are licensed under the repo's
MIT license.
