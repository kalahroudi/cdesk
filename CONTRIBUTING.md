# Contributing

Thanks for helping. CDesk is a small, light app and we want to keep it that way.

## Ground rules

- **Stay light.** No third-party dependencies, no background polling while the popover and Manager are closed, no embedded terminals or web views.
- **Keep the core UI-free.** Anything that talks to `colima` or `docker`, parses their output, or decides what to recommend belongs in `Sources/ColimaKit` with a unit test. The app and the MCP server both use it.
- **Be careful with data.** Anything that can delete data (recreate, volume remove, prune) must ask for confirmation: the name for data loss, confirm/cancel for the rest. MCP tools that delete need an explicit `confirm` argument.
- **Explain things.** New options get a "?" tip that says what it is and why it matters, and an entry in the glossary if it introduces a term.
- **Never test destructive actions on your real VM.** Use a throwaway profile: `colima start scratch --cpus 2 --memory 2`.

## Workflow

```sh
swift build
swift test
swift run CDesk            # try it
scripts/bundle.sh          # build dist/CDesk.app (needed to test updates and launch at login)
```

Open an issue before large changes. Pull requests should include tests for `ColimaKit` changes and, for UI changes, a screenshot (`CDesk --snapshot out/` renders the screens with sample data).

## Releases

Maintainers push a tag: `git tag v0.2.0 && git push origin v0.2.0`. The Release workflow tests, builds the disk image and publishes it with `SHA256SUMS`. Add the repository secrets `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID` and `NOTARY_PASSWORD` to sign and notarise.

## License

By contributing you agree that your contributions are licensed under the Apache License 2.0.
