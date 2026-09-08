Contributing
============

Thanks for considering a contribution to OSDCloud. This project welcomes fixes,
documentation updates, and new features that improve Windows deployment
workflows.

Before you start
----------------
- Review the [docs index](docs/README.md) for an overview of the user-facing guides.
- Check open issues to avoid duplicating work: https://github.com/OSDeploy/OSDCloud/issues
- Read the module architecture section in [.github/copilot-instructions.md](.github/copilot-instructions.md) for a directory map.

Getting started locally
-----------------------
1. Fork the repository and clone your fork.
2. Import the module directly from the source tree — no build step is required:
   ```powershell
   Import-Module .\OSDCloud\OSDCloud.psd1 -Force
   ```
3. Create a feature branch with a short, descriptive name (e.g., `fix-wifi-dhcp-retry`).
4. Make focused changes — one logical topic per pull request.
5. Test in a Windows or WinPE environment when applicable.

Branch naming
-------------
Use `<scope>/<description>` where `<scope>` is one of the commit scopes
listed below. Example: `deployment/fix-bcdboot-uefi`.

PowerShell coding conventions
------------------------------
All PowerShell files in this project must follow these rules. They are also
enforced by the `.github/instructions/powershell.instructions.md` instruction
file.

**Every function must:**

- Use `[CmdletBinding()]` — no exceptions.
- Include comment-based help with all required sections:
  `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` (one per parameter), `.EXAMPLE`
  (at least one), `.OUTPUTS`, `.NOTES`.
- Use full cmdlet names — no aliases in scripts (e.g. `Get-ChildItem`, not `gci`).
- Log with the standard verbose pattern:
  ```powershell
  Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] <message>"
  ```
- Clear the error collection at the start: `$Error.Clear()`.

**Do not** use `begin`/`process`/`end` blocks unless the function is genuinely
pipeline-oriented (accepts pipeline input in a loop). OSDCloud functions are
single-call and procedural.

**Naming conventions:**

| Item | Convention |
|---|---|
| Functions | `Verb-Noun` PascalCase; use an approved verb (`Get-Verb`) |
| Parameters | PascalCase |
| Module/public variables | PascalCase |
| Local/private variables | camelCase |

**WinPE-only code:**

- Guard any WinPE-only logic with `$env:SystemDrive -eq 'X:'`.
- Place WinPE-only exported functions in `public/WinPE/`. Functions in this
  directory are **not loaded** in a normal Windows session.

Documentation requirements
--------------------------
- **New exported function** — create a reference page in `OSDCloud/docs/`
  following the PlatyPS schema 2.0.0 used by the existing pages. Fill in all
  sections; do not leave `{{ Fill ... }}` placeholders.
- **Changed exported function signature** — update the corresponding
  `OSDCloud/docs/<FunctionName>.md` reference page.
- **New behaviour or concept** — add or update a guide in
  `docs/`.
- **README** — update the Commands table and Documentation section if you add
  or rename an exported cmdlet.

Adding a deployment step
------------------------
1. Implement the step function in `private/steps/` following the naming
   convention `step-<Verb>-<Noun>.ps1`.
2. Add a JSON entry to the appropriate `workflow/<channel>/tasks/<task>.json`.
3. Follow the JSON schema documented in
   `.github/instructions/workflow-tasks.instructions.md`.
4. Add a row for the new step to the phase table in
   [docs/05-customize-deployment.md](docs/05-customize-deployment.md).

Catalog updates
---------------
When adding a new OS build, Surface model, or OEM driver pack version see
`.github/instructions/osdcloud-catalog-update.instructions.md` for the
required file naming, XML/JSON schema, and build-number switch statement
changes.

Testing
-------
No automated tests exist yet. When adding tests:

- Use Pester v5. Follow `.github/instructions/powershell-pester-5.instructions.md`.
- Place the test file adjacent to the function being tested:
  `<FunctionName>.Tests.ps1`.
- Mock **all** external dependencies (WMI/CIM, network calls, disk operations).
- Do not write tests that require a WinPE environment to run.

Pull request checklist
----------------------
Before opening a PR, confirm the following:

1. [ ] All new/changed functions have `[CmdletBinding()]`.
2. [ ] All new/changed functions have complete comment-based help.
3. [ ] No aliases are used in scripts (`gci`, `%`, `?`, etc.).
4. [ ] WinPE-only functions are in `public/WinPE/`.
5. [ ] `OSDCloud/docs/` reference page created or updated for each changed function.
6. [ ] No `{{ Fill ... }}` placeholders remain in any docs file.
7. [ ] `CHANGELOG.md` entry added under the next version number.
8. [ ] `README.md` Commands and Documentation tables updated if cmdlets were added or renamed.
9. [ ] Commit message follows the format in `.github/instructions/commit-messages.instructions.md`.
10. [ ] Changes tested in a Windows session (and WinPE if applicable).

Commit message format
---------------------
See `.github/instructions/commit-messages.instructions.md` for the full format.
Valid scopes: `workflow`, `driver-packs`, `pe-startup`, `deployment`, `classes`,
`catalog`, `core`, `wi-fi`, `main`.

How to contribute
-----------------
1. Fork the repository.
2. Create a feature branch.
3. Make focused changes.
4. Complete the pull request checklist above.
5. Open a pull request with a concise summary and any relevant context.

Intellectual property
---------------------
By submitting a pull request or patch, you agree to assign all right, title,
and interest in your contribution to Recast Software for inclusion in OSDCloud.
You represent that the contribution is your original work or that you have the
rights to submit it. If your employer or another party has rights to your work,
you are responsible for obtaining any required permissions before contributing.

Issues
------
When opening an issue, include:
- What you expected to happen
- What actually happened
- Steps to reproduce
- PowerShell version and OS/WinPE details

Code of conduct
---------------
Be respectful and constructive. This project follows standard open-source
collaboration norms.
