# Password-protected BootMenu environment variables

Use `encryptedEnv` in an `osdcloudbootmenu.json` profile to store encrypted string
tokens instead of plaintext values. BootMenu asks for a password after selecting
the profile, including when a single profile is auto-selected. No archive or
7-Zip dependency is involved.

This is for **OSDCloudBootMenu**, not legacy `Invoke-WinpeStartup` profiles.
Use an updated OSDCloud package containing these commands and rebuild the boot
image with OSDCloud Boot. Older runtimes reject the new profile section.

## Require a password to start a profile

The builder's **OSDCloud BootMenu Profiles** card has an overflow menu for a
single selected profile:

- **View** opens a read-only JSON preview.
- **Clone** copies any profile and its supporting files into OSDeployCore.
- **Edit in VS Code** is available only for editable OSDeployCore profiles,
  never built-in module profiles.
- **Set Password** requests and confirms a masked password. For a built-in
  profile, it then asks for a clone name and protects that copy, leaving the
  original unchanged.

Set Password writes an authenticated `OSDBS1:` token to the optional top-level
`password` property. It does not store the password itself. Selecting or
auto-selecting that profile in WinPE requires the password before any selected
profile assets, Import Packs, or commands run. The normal WPF flow uses a masked
password dialog; `-CLI` uses a masked console prompt. Incorrect passwords retry;
Cancel, closing the dialog, or empty console input stops the selected profile
without falling back to deployment. Rebuild boot media after setting a password.

For automation, use `Invoke-OSDCloudBootMenu -ProfilePassword $password` with a
SecureString. An incorrect supplied password terminates rather than prompting.
Cloning a protected profile preserves its password. Set Password again to change
it, or remove its `password` property in VS Code to remove the selection gate.

**This is an access prompt, not encryption of the profile or its scripts.**
Someone able to modify boot media can remove or bypass it. Build-level
initialization before selection is not gated. Use trusted media.

The profile password is separate from the `encryptedEnv` password described
below. A profile containing both will prompt separately; `ProfilePassword` does
not automatically unlock its encrypted variables.

## Create tokens on the technician PC

Import the standalone runtime bundled with OSDCloud. These commands are exported
by `OSDCloudBootMenu`, not the parent `OSDCloud` or builder `OSDCloudBoot` module.

```powershell
$osdcloud = Get-Module -ListAvailable OSDCloud |
    Sort-Object Version -Descending | Select-Object -First 1
if (-not $osdcloud) { throw 'Install an updated OSDCloud package first.' }
Import-Module (Join-Path $osdcloud.ModuleBase 'core\modules\OSDCloudBootMenu\OSDCloudBootMenu.psd1')

# Synthetic values only. For real secrets, avoid literals in command history.
$password = Read-Host -Prompt 'Choose one password for this profile' -AsSecureString
try {
    $serviceToken = Protect-OSDCloudBootString -InputString 'Synthetic service value' -Password $password
    $wifiToken = Protect-OSDCloudBootString -InputString 'Synthetic Wi-Fi value' -Password $password
}
finally { $password.Dispose() }
```

`$serviceToken` and `$wifiToken` are copyable strings beginning with `OSDBS1:`.
Each encryption uses a fresh salt and IV, so encrypting identical values produces
different tokens. Without `-Password`, `Protect-OSDCloudBootString` prompts twice
with masked input and verifies the confirmation.

## Add tokens to a BootMenu profile

Add the tokens to an existing profile in
`C:\ProgramData\OSDeployCore\boot-assets\bootmenu-profiles\<name>\osdcloudbootmenu.json`.
For example, replace the placeholders below with the generated token strings;
placeholders themselves do not pass validation.

```json
{
  "schemaVersion": 1,
  "info": {
    "id": "652dca24-393f-46a1-ae8c-345a432a9078",
    "name": "Password-protected deployment"
  },
  "env": {
    "DEPLOYMENT_REGION": "West"
  },
  "encryptedEnv": {
    "SERVICE_TOKEN": "<paste $serviceToken here>",
    "WIFI_PASSWORD": "<paste $wifiToken here>"
  },
  "osdcloudBootStartup": {
    "main": {
      "commands": [
        "& 'X:\\OSDCloud\\Scripts\\Deploy-Site.ps1'"
      ],
      "errorAction": "Stop"
    }
  }
}
```

Supply your own consuming script in the image. It can read `$env:SERVICE_TOKEN`
and `$env:WIFI_PASSWORD`; it should not print them or place them on native command
lines. For a new profile, generate a unique ID with `[guid]::NewGuid()`.

All entries in `encryptedEnv` must use the **same password**. Recreate tokens if
different passwords were used. Names must match `[A-Za-z_][A-Za-z0-9_]*`, be unique
case-insensitively, and not also appear in `env`.

## Runtime behavior

1. Rebuild the image with the updated runtime and selected profile, then boot it.
2. BootMenu selects the profile and requests the shared password using a masked
   console prompt. No prompt occurs for profiles without encrypted variables.
3. An incorrect password or modified authenticated content permits another attempt.
   Empty input or Ctrl+C cancels the selected profile. Invalid/unsupported token
   formats stop execution rather than requesting passwords repeatedly.
4. All values must decrypt before any are assigned. Selected-profile assets and
   commands do not run if unlocking fails or is cancelled.
5. Selected-profile `.env` assets are imported, then unlocked values take precedence
   for their names before selected-profile Import Pack scripts and command phases.
6. Original parent-process values are restored when BootMenu exits, including on
   errors. Child processes retain the values inherited at launch.

System-wide initialization and build-level Import Pack scripts already run before
profile selection; the password does not gate those actions.

For automation, pass a SecureString with
`Invoke-OSDCloudBootMenu -EnvironmentPassword $password`. A supplied incorrect
password terminates instead of prompting. Do not store the password in the profile.
The encrypted environment is not license-gated; existing asset licensing is unchanged.

To decrypt a token explicitly:

```powershell
$value = Unprotect-OSDCloudBootString -Token $serviceToken
```

This command prompts once and returns plaintext. Capture it rather than printing
it to a console or transcript. It also accepts `-Password`.

## Format and security boundaries

- Version 1 uses PBKDF2-HMAC-SHA256 with 600,000 iterations, a random 32-byte salt,
  AES-256-CBC/PKCS7 with a random 16-byte IV, and an independent HMAC-SHA256 key.
  The HMAC is checked before decryption.
- The token is `OSDBS1:` followed by Base64 of: version byte `01`, salt, IV,
  ciphertext, and a 32-byte HMAC over all preceding bytes. The fixed version
  determines algorithms and work factor; no machine-bound DPAPI is used.
- Windows PowerShell 5.1 requires .NET Framework 4.7.2 or newer for the SHA256
  PBKDF2 API. Verify the actual amd64 and arm64 WinPE images; host tests alone
  cannot certify either boot environment.
- Commands accept up to 1 MiB of UTF-8 plaintext. Environment values must be
  nonempty, contain no NUL character, and contain at most 32,766 UTF-16 code units.
  General string encryption supports empty strings; environment assignment does not.
- Use a strong password: copied tokens permit offline guessing. There is no
  password recovery or protection against a weak password.
- This protects values at rest, not an unlocked session. Environment variables
  are plaintext, process-readable, and inherited by children. Prefer short-lived,
  limited-scope credentials. Immutable .NET strings cannot be reliably erased.
- The implementation does not log secrets, but consuming scripts, environment
  dumps, debugging, or explicitly displaying decrypted output can expose them.
- Encrypted tokens do not sign the surrounding profile or scripts. An attacker
  who can replace boot-media code can capture the password. Use trusted media.

Function help lives in PowerShell source. Where OSDCloudBoot generated help needs
refreshing, use its existing **Generate PowerShell Help** workflow; do not edit
generated Markdown or en-US help directly.
