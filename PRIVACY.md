Privacy Policy
==============

Effective date: July 22, 2026

Summary
-------

OSDCloud is a PowerShell module that runs locally. It collects device and deployment information so it can select operating system content, match driver packs, display deployment details, and write diagnostic logs. Some workflow tasks also send a deployment analytics event to PostHog.

The module transmits data only when a command or workflow performs a network operation, such as sending deployment analytics, checking internet connectivity, checking Microsoft Update Catalog or PowerShell Gallery availability, retrieving catalog metadata, running a user-provided startup URL, or downloading operating system, firmware, driver, or module content.

Deployment Analytics
--------------------

Before workflow steps run, `Invoke-OSDCloudWorkflowTask` sends a `Deploy-OSDCloud` event to PostHog at `https://us.i.posthog.com/capture/`. The event is sent over HTTPS with a two-second timeout. If the request fails, the failure is logged at verbose level and deployment continues.

The analytics event includes:

- A hashed device identifier derived from the device UUID (see below)
- Device details used for driver matching and reporting, including manufacturer, model, product, system family, system product, SKU, and system type
- BIOS details, including release date and SMBIOS BIOS version when available
- Keyboard name and layout
- Windows environment details, including architecture, build, build lab, country code, edition, installation type, language, name, time zone, and version
- OSDCloud workflow details, including workflow name, task name, selected driver pack name, selected OS name, version, activation status, build, build version, and language code
- OSDCloud module version and deployment phase (WinPE or Windows)
- Event timestamp

`Deploy-OSDCloud` also sends an `OSDCloudResults` event after a started workflow
returns or raises a terminating error, before the command's PostAction. This
additional event uses a reduced summary:

- Schema version and a new deployment GUID for the invocation
- Hashed-device analytics distinct ID (or a random fallback GUID)
- Lifecycle status, completion flag, UTC start/end timestamps, and numeric workflow duration in seconds
- Actual acquired OS and driver-pack sizes (`sizeOS`, `sizeDriverPack`) in whole MB, their combined size (`totalSizeMB`), and overall throughput (`totalMBps`) calculated from combined size and deployment duration. Separate local downloads (`totalSizeDownloadMB`), USB-cache downloads (`totalSizeCacheMB`), and copied/reused content (`totalSizeCopyMB`) are also included. USB-cache downloads are excluded from the local-download total; subsequent local copies contribute to the copy total. Each transfer total rounds combined original bytes once.
- `ContentInternet` is `totalSizeCacheMB + totalSizeDownloadMB`. `ContentLocal` counts only copied/reused content already available locally, excluding content downloaded during this deployment (to USB cache or directly) even if subsequently copied. Eligible original bytes are summed before rounding once to whole MB (1 MB = 1,048,576 bytes); this avoids subtracting independently rounded totals or downloads that were never copied. Both properties remain null until content is acquired. `totalSizeMB = sizeOS + sizeDriverPack` sums the individually rounded acquired content sizes once, not transfer traffic or the expanded Windows footprint. Content downloaded and subsequently copied contributes to internet content, not local content, and only once to `totalSizeMB`.
- OS and driver-pack local download, USB-cache download (`stepOSCache`, `stepDriverPackCache`), copy, and expansion timing, with matching rates in whole MB/s calculated from reported sizes and seconds; unavailable rates are null.
- Network connection category (`Wired` or `Wireless`), or null when unavailable or ambiguous. No adapter names, gateway addresses, or Wi-Fi network names are included in results analytics.
- Combined OS/driver-pack origin (`ContentSource`): `Cloud` for new downloads (including USB-cache downloads), `Cache` for pre-existing content, or `Mixed` for both origins. Only obtained content contributes; unknown origin or no obtained content produces null.
- Separate whole-second OS and driver-pack copy, download, and expansion durations; disk-cleaning confirmation wait; and total duration excluding that confirmation wait (`totalDuration`)
- Aggregate whole-second download, USB-cache download, copy, and expansion durations; combined cloud time (download plus USB-cache download); and remaining workflow time after subtracting all reported step durations
- Module version, workflow/task name, CLI or GUI launch method, and WinPE or Windows deployment environment
- Manufacturer, model, product, processor architecture, and physical memory capacity
- Selected OS name, version, build, build version, edition, activation channel, language, and file name; selected driver pack name and file name. ModelDrivers is pre-existing cached folder content, so its driver pack file name is null and its size is the total file size in the local staging folder after copying.

The completion flag means workflow execution reached the pre-PostAction boundary,
not that every step succeeded. Duration excludes initialization, GUI selection,
results reporting, and the command's PostAction. Durations are rounded to whole
seconds. `totalDurationRAW` replaces the earlier `DurationSeconds` property. All phase
timings use a `step` prefix. Separate copy/download timings exclude cache lookup,
availability checks, hash verification, extraction, and injection. Expansion
timings measure Windows image application and driver archive extraction during the
deployment, not driver installation deferred to SetupComplete. `stepClearDisk`
measures only confirmation response time, not disk-cleaning execution.
`totalDuration` is the total minus that wait, treating an absent wait as zero.
Size
uses 1 MB = 1,048,576 bytes; each transfer total is rounded from original byte
counts, not summed rounded sizes. Cached content contributes only to the copy
total. Totals do not measure retries or network overhead. GUI cancellation and initialization failures do not send the
new event. The request uses HTTPS and a two-second timeout; failures warn and
deployment continues. The original, more detailed start event remains unchanged.
Standalone deployment helpers and direct workflow invocation do not add the new
terminal event.

The new event excludes raw device and license identifiers, BIOS/keyboard/host-Windows
details, local paths, download URLs, and exception messages. Its explicit property
allowlist prevents additional properties added to the local results object from
being transmitted.

The analytics payload does not intentionally include usernames, email addresses, device serial numbers, computer names, hardware hashes, MAC addresses, IP addresses, or raw UUID values. Network metadata such as source IP address, request headers, and timestamps may still be processed by PostHog as part of receiving the HTTPS request.

**Device identifier hashing**

The analytics distinct ID is derived from the device UUID obtained from WMI. Before transmission, the UUID is hashed with **SHA-256** and the resulting hex digest is used as the identifier. This process is one-way: the original UUID is not sent in the analytics event and cannot be recovered from the hash by OSDCloud.

If no distinct ID is produced, OSDCloud generates a random GUID for that run and uses it instead.

Local Device Data and Logs
--------------------------

OSDCloud gathers device information locally through WMI/CIM and related Windows tools. This information is used for deployment decisions, device matching, troubleshooting, and UI display. Local data may include:

- Device manufacturer, model, product, SKU, system family, chassis type, processor, memory, disk, BIOS, TPM, Secure Boot, and firmware details
- Device serial number, computer name, UUID, hardware hash when `oa3tool.exe` is available, and other values returned by WMI/CIM classes
- Network adapter names, IP addresses, MAC addresses, gateways, and adapter configuration
- Operating system, time zone, keyboard, and system environment details
- Deployment selections, workflow settings, downloaded file paths, and step results

Diagnostic files are written under `$env:TEMP\osdcloud-logs`. When an `OSDCloudLogs` folder is available on a writable drive, logs may also be copied to `OSDCloudLogs\<device serial number>`. These local logs can contain device identifiers and environment details. They are not sent to PostHog by OSDCloud, but they may be visible to anyone with access to the deployment media, local disk, network share, or copied log package.

`Deploy-OSDCloud` creates `$global:OSDCloudResults` with the reduced summary described
above. It overwrites `OSDCloudResults.clixml` directly in current `$env:TEMP` at
workflow start and termination, and in the deployed Windows volume's `Windows\Temp`
at termination when that directory is available. Cancellation and initialization
failure save only to current TEMP. The local object and snapshots include the
pseudonymous analytics identifier, which can correlate deployments on the same
device; it should not be treated as fully anonymous. An interrupted deployment may
leave a snapshot marked `Running`. These snapshots are separate from the diagnostic
log directory and are accessible to anyone with access to those locations.

Some graphical workflow screens display the device serial number, UUID, and hardware hash when available and provide copy-to-clipboard actions for operator convenience. Displaying or copying these values is local to the deployment session.

What Data May Be Shared
-----------------------

- Deployment analytics events include the fields described in the Deployment Analytics section.
- Connectivity and time checks send standard HTTP HEAD requests to endpoints such as Microsoft connectivity test services or Google, depending on the workflow path.
- Catalog lookups and content downloads send standard HTTP or HTTPS requests to Microsoft, GitHub, OEM, PowerShell Gallery, or other selected content endpoints.
- User-provided WinpeStartup command URLs may be fetched and executed if configured by the operator.
- Third-party services you connect to may log network metadata such as IP address, request headers, requested URL, and timestamp.

External Services
-----------------

OSDCloud may interact with external services when you choose to download content, update the module, or run workflows. Those services have their own privacy policies. Examples include:

- **Microsoft Update Catalog and Microsoft download services** - used to query and download operating system images, firmware, drivers, and Surface packages. See the [Microsoft Privacy Statement](https://privacy.microsoft.com/privacystatement).
- **Microsoft connectivity test services and Google** - used by some startup or time synchronization paths to test internet connectivity or read an HTTP Date header.
- **GitHub** - used for project hosting, issue tracking, and raw catalog metadata. See the [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).
- **PowerShell Gallery** - used for module availability checks and updates. Governed by the Microsoft Privacy Statement.
- **OEM driver sites** - Dell, HP, Lenovo, Panasonic, Microsoft Surface, and other selected driver pack sources may be queried or downloaded from vendor-hosted servers. Consult each vendor's privacy policy.
- **PostHog** - deployment analytics. Events are sent to `https://us.i.posthog.com`. See the [PostHog Privacy Policy](https://posthog.com/privacy).
- **Operator-provided URLs** - WinpeStartup workflows can be configured to download and execute commands from URLs provided by the operator. Those endpoints are controlled by the operator or their organization.

Your Choices
------------

- You control when network requests happen by choosing which commands and workflow steps to run.
- Analytics events are sent when `Invoke-OSDCloudWorkflowTask` runs. Commands that only display information, such as `Show-OSDCloudDeviceInfo` or `Get-OSDCloudModuleVersion`, do not send analytics events.
- To avoid deployment analytics entirely, do not run deployment workflow commands that call `Invoke-OSDCloudWorkflowTask`, including normal `Deploy-OSDCloud` workflow execution.
- To limit local diagnostic data, review and delete local log files from `$env:TEMP\osdcloud-logs` and any writable `OSDCloudLogs` destination after deployment, subject to your organization's troubleshooting and retention requirements.
- Also review and delete `OSDCloudResults.clixml` from current TEMP and the deployed Windows `Windows\Temp` directory according to your organization's retention requirements.

Contact
-------

For questions or concerns, open an issue at <https://github.com/OSDeploy/OSDCloud/issues>.
