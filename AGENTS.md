# Repository guidance

## Project overview

This repository contains a Flutter-based SKALA attendance helper.

- Android supports external Google authentication, attendance status lookup,
  and attendance actions after an App Link callback.
- iOS currently supports profile and schedule management, local reminders, and
  opening the external browser for manual attendance handling.
- The app does not perform unattended Google authentication or silently send
  attendance actions while the device is locked.
- Treat `docs/current-implementation.md` as the source of truth for the current
  feature scope.
- Keep historical investigation and abandoned plans in
  `docs/implementation-notes.md`; do not rewrite them as if they were current.

## Repository layout

- `lib/app`: application composition and startup
- `lib/features/*/application`: controllers and use-case orchestration
- `lib/features/*/data`: API, persistence, and platform integrations
- `lib/features/*/domain`: models and business rules
- `lib/features/*/presentation`: Flutter screens and widgets
- `test`: unit and widget tests
- `android`, `ios`: platform-specific configuration
- `docs`: current implementation, design decisions, and historical research

## Engineering conventions

- Preserve the feature-based `application`, `data`, `domain`, and
  `presentation` boundaries.
- Do not place HTTP calls, persistence, or platform-channel logic directly in
  presentation widgets.
- Keep attendance eligibility and confirmation rules deterministic and covered
  by unit tests when possible.
- Make platform differences explicit. Do not imply that iOS supports the
  Android App Link attendance flow until it is implemented and verified on a
  real iOS device.
- Never store or log Google passwords, browser cookies, full attendance tokens,
  public API service keys, or other secrets.
- Keep attendance tokens in memory unless the user explicitly approves a new
  secure-storage design.
- Never send a real attendance action merely to test the application. A real
  action requires the user's explicit intent at an appropriate attendance time.
- Preserve unrelated user changes in a dirty worktree.

## Validation

Format affected Dart files and run the checks relevant to the change. For a
normal code change, use:

```sh
dart format <changed-dart-files>
flutter analyze
flutter test
```

For Android platform configuration, notification behavior, authentication, or
release-related changes, also build an APK when the environment permits:

```sh
flutter build apk --debug
```

Do not claim a real-device flow was verified unless it was actually installed
and exercised on the device. Documentation-only changes normally require link,
format, and `git diff --check` validation rather than a Flutter build.

## Git workflow

- Start each coherent change on a dedicated branch without waiting for the user
  to request it. Use `feat/<name>` for features, `fix/<name>` for fixes, and
  `docs/<name>` for documentation-only work. If the current branch already
  represents the same change, continue using it instead of creating another
  branch.
- Follow Conventional Commits prefixes such as `feat:`, `fix:`, `docs:`,
  `refactor:`, `test:`, and `chore:`.
- Keep logically separate documentation, implementation, and cleanup work in
  separate commits when that improves reviewability.
- When a coherent unit of work is implemented and verified, commit the scoped
  changes with a suitable Conventional Commit message without waiting for a
  separate user request. Never include unrelated user changes in that commit.
- A successful implementation and automated checks do not authorize merging.
  Keep the completed branch checked out so the user can verify the behavior
  directly.
- Treat an explicit user statement that the verified feature is satisfactory
  as authorization to finish the branch: commit any remaining scoped changes,
  push the feature branch, switch to `main`, merge the feature branch, verify
  the merged result, and push the updated `main` when a remote is configured.
  Complete this integration before starting the user's next requested change.
- Do not push, switch branches, merge, or delete the feature branch before that
  explicit user acceptance. Do not infer acceptance merely from a request to
  continue discussing or adjusting the feature.
- When a feature branch is ready, tell the user which branch to merge and note
  any checks that should run before merging.
- When a stable, integrated `main` commit is ready, suggest an appropriate
  version tag if it represents a meaningful release milestone.
- Do not create tags or publish GitHub releases unless the user explicitly
  requests that action.

## Version tags and releases

- Do not create a tag for every feature branch.
- Tag integrated and verified commits on `main`.
- Use `v0.1.0-alpha.N` for early internal prototypes,
  `v0.1.0-beta.N` for feature-complete test builds, and `v0.1.0` or later for
  stable releases.
- Before recommending a tag, check for uncommitted changes and confirm that the
  intended changes are already included in the tagged commit.
- A tag does not automatically include later commits; explain this when it is
  relevant to the user's workflow.

## Documentation maintenance

- Update `README.md` when user-visible capabilities, platform support, setup, or
  primary document links change.
- Update `docs/current-implementation.md` when implemented or intentionally
  unsupported behavior changes.
- Update the appropriate design-decision document when its assumptions or
  tradeoffs change.
- Preserve historical reasoning. Prefer a current-status note or a new document
  over deleting useful investigation history.
- Keep `docs/README.md` accurate when documents are added, renamed, or change
  status.

## Definition of done

A requested change is complete when:

- the requested behavior is implemented;
- relevant tests are added or updated;
- formatting, analysis, and tests pass in proportion to the change;
- affected documentation reflects the actual behavior;
- no secret or unrelated user change was introduced; and
- the final handoff states what changed, what was verified, any remaining
  limitation, and a suitable commit message when the work forms a commit-worthy
  unit.
