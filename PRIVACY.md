Privacy Policy
==============

Effective date: July 22, 2026

Summary
-------

OSDCloud is a PowerShell module that runs locally. It collects device and deployment information so it can select operating system content, match driver packs, display deployment details, and write diagnostic logs. Some workflow tasks also send a deployment analytics event to PostHog.

The module transmits data only when a command or workflow performs a network operation, such as sending deployment analytics, checking internet connectivity, checking Microsoft Update Catalog or PowerShell Gallery availability, retrieving catalog metadata, running a user-provided startup URL, or downloading operating system, firmware, driver, or module content.

Deployment Analytics
--------------------

During workflow task execution, `Invoke-OSDCloudWorkflowTask` sends an `osdcloud_deploy` event to PostHog at `https://us.i.posthog.com/capture/`. The event is sent over HTTPS with a two-second timeout. If the request fails, the failure is logged at verbose level and deployment continues.

The analytics event includes:

- A hashed device identifier derived from the device UUID (see below)
- Device details used for driver matching and reporting, including manufacturer, model, product, system family, system product, SKU, and system type
- BIOS details, including release date and SMBIOS BIOS version when available
- Keyboard name and layout
- Windows environment details, including architecture, build, build lab, country code, edition, installation type, language, name, time zone, and version
- OSDCloud workflow details, including workflow name, task name, selected driver pack name, selected OS name, version, activation status, build, build version, and language code
- OSDCloud module version and deployment phase (WinPE or Windows)
- Event timestamp

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

Some graphical workflow screens display the device serial number, UUID, and hardware hash when available and provide copy-to-clipboard actions for operator convenience. Displaying or copying these values is local to the deployment session.

What Data May Be Shared
-----------------------

- Deployment analytics events include the fields described in the Deployment Analytics section.
- Connectivity and time checks send standard HTTP HEAD requests to endpoints such as Microsoft connectivity test services or Google, depending on the workflow path.
- Catalog lookups and content downloads send standard HTTP or HTTPS requests to Microsoft, GitHub, OEM, PowerShell Gallery, or other selected content endpoints.
- User-provided WinPEStartup command URLs may be fetched and executed if configured by the operator.
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
- **Operator-provided URLs** - WinPEStartup workflows can be configured to download and execute commands from URLs provided by the operator. Those endpoints are controlled by the operator or their organization.

Your Choices
------------

- You control when network requests happen by choosing which commands and workflow steps to run.
- Analytics events are sent when `Invoke-OSDCloudWorkflowTask` runs. Commands that only display information, such as `Show-OSDCloudDeviceInfo` or `Get-OSDCloudModuleVersion`, do not send analytics events.
- To avoid deployment analytics entirely, do not run deployment workflow commands that call `Invoke-OSDCloudWorkflowTask`, including normal `Deploy-OSDCloud` workflow execution.
- To limit local diagnostic data, review and delete local log files from `$env:TEMP\osdcloud-logs` and any writable `OSDCloudLogs` destination after deployment, subject to your organization's troubleshooting and retention requirements.

Contact
-------

For questions or concerns, open an issue at <https://github.com/OSDeploy/OSDCloud/issues>.
