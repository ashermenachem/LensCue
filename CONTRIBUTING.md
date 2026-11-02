# Contributing to LensCue

Thanks for helping make a small, useful tool better.

## Start here

- Report reproducible problems through the bug form in Issues.
- Use Discussions for questions, feedback and larger ideas.
- For a substantial change, discuss the approach before opening a large pull request.

## Local development

Use macOS with Xcode 16+ and a Swift 6 toolchain:

```bash
git clone https://github.com/ashermenachem/LensCue.git
cd LensCue
swift test
./script/build_and_run.sh
```

`CueCore` owns matching and sound-level gating; the executable owns native UI and Apple speech/audio integration. `./script/build_and_run.sh --package` builds an optimized, ad-hoc-signed archive for the current architecture. Generated apps and build caches belong in ignored directories, not in Git.

## Pull requests

Keep changes focused. Explain the user-visible problem, resulting behavior and validation. Add meaningful tests when changing word matching or voice gating. For overlay changes, include a screenshot and describe notch/display behavior. Never include personal scripts, audio recordings, credentials or local machine paths.

Use system frameworks where practical. Keep a working offline path, clear error messages and accessible controls. Do not add analytics or cloud recognition without a prior project discussion.

By contributing, you agree that your contribution is available under the repository's MIT license. Be respectful, keep feedback constructive, and give others room to ask questions.
