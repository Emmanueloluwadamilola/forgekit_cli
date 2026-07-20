# Security Policy

## Supported versions

ForgeKit `0.1.x` is a Git-distributed public beta. Security fixes are provided
for the latest reviewed commit published with the current beta release notes;
older commits and arbitrary development checkouts are unsupported. Because the
project is pre-1.0, generated-code and CLI compatibility may change between
minor releases and will be documented in `CHANGELOG.md`.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability and do not include
credentials, tokens, private source code, or personal data in a report.

Use the repository's private
[Report a vulnerability](https://github.com/Emmanueloluwadamilola/forgekit_cli/security/advisories/new)
form. Include:

- The affected ForgeKit commit SHA or release version.
- The operating system, Dart version, and Flutter version.
- A minimal reproduction with sensitive values replaced.
- The expected and actual security boundaries.
- The likely impact and any known workaround.

If the report contains a live credential, revoke or rotate it before reporting.
Please allow the maintainer time to reproduce and fix the issue before public
disclosure.

## Scope

Useful reports include command injection, path traversal, unsafe overwrite or
rollback behavior, credential disclosure, insecure update or registry behavior,
and generated code that materially weakens an application's security boundary.

Generated Flutter applications still require their own threat model, dependency
review, server-side authorization, secret management, and platform security
assessment. ForgeKit cannot make a secret safe once it is bundled into a client
application.
