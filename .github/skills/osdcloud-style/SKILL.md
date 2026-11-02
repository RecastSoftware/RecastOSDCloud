---
name: osdcloud-style
description: 'Apply the Deploy-OSDCloud WPF visual style. Use whenever adding, editing, or reviewing the deployment settings GUI, workflow MainWindow.xaml or MainWindow.ps1, Device and Identity tabs, OS and driver-pack selectors, menus, logo, Start button, typography, colors, spacing, resizing, keyboard focus, or accessibility. Preserve workflow-specific UI overrides and distinguish the default light deployment UX from the dark BootMenu and OSDCloud Boot builder.'
---

# OSDCloud Deployment Style

## Scope and References

Keep the Deploy-OSDCloud settings interface consistent with the active workflow.
The default deployment UX is a light, conventional WPF window, not the dark
OSDCloud Boot builder or runtime BootMenu. Creating this skill does not authorize
a theme migration or changes to deployment behavior.

- Public entry point: [Deploy-OSDCloud.ps1](../../../OSDCloud/public/WinOS/Deploy-OSDCloud.ps1)
- GUI confirmation and workflow handoff: [Deploy-OSDCloudGUI.ps1](../../../OSDCloud/private/Deploy-OSDCloudGUI.ps1)
- Workflow UI resolution: [Invoke-OSDCloudWorkflowUI.ps1](../../../OSDCloud/private/workflow/Invoke-OSDCloudWorkflowUI.ps1)
- Default executable layout: [MainWindow.xaml](../../../OSDCloud/workflow/default/ux/MainWindow.xaml)
- Default UI population and events: [MainWindow.ps1](../../../OSDCloud/workflow/default/ux/MainWindow.ps1)
- Default application resources: [App.xaml](../../../OSDCloud/workflow/default/ux/App.xaml)
- Default logo: [logo.png](../../../OSDCloud/workflow/default/ux/logo.png)
- Behavior tests: [Deploy-OSDCloud.Tests.ps1](../../../OSDCloud/public/WinOS/Deploy-OSDCloud.Tests.ps1)
- Initialization tests: [Initialize-DeployOSDCloud.Tests.ps1](../../../OSDCloud/private/Initialize-DeployOSDCloud.Tests.ps1)

Read the active workflow's executable UI, control construction, and event
handlers before editing. The loader prefers a workflow's `ui\MainWindow.ps1`,
then `ux\MainWindow.ps1`, with default-workflow fallback. Do not assume every
deployment uses the default XAML or apply default styling to workflow overrides
without an explicit request.

## Default Visual Language

The default XAML uses local property values, not the BootMenu's named brush
dictionary. Its application resource section is empty. Follow existing local
patterns; do not reference nonexistent `SurfaceBrush`, `CardStyle`, or
`OptionToggleStyle` resources.

| Role | Current default |
|---|---|
| Window background | `#FFF6F8FF` |
| Menu/tab surfaces | White |
| Menu/tab borders | `#DDE5F5` |
| Label foreground | `#3b455a` |
| Read-only/detail text | `DarkGray` |
| Clickable identity values | Blue |
| Start background and border | `#0372FF` |
| Start foreground | White |

- Preserve the existing WPF control typography. The default window does not
  declare a global font family; do not claim a Segoe UI Variable font stack
  or dark-theme typography resource already exists.
- Match neighboring labels' bold/semibold treatment and retain the distinction
  between labels, read-only values, and clickable identity values.
- Keep the blue, white-text Start button at 128 by 40 DIPs with 16-DIP
  semibold text and default-button behavior unless the request changes these.
- Use the existing workflow-local `logo.png` through `LogoImage` and its runtime
  assignment. Preserve its 40-DIP height, uniform scaling, `0,0,0,4` margin,
  and space for the action area.
- The default UI has text menus rather than a font-icon system. Do not import
  BootMenu glyphs, sidebar chrome, builder branding, Build/Task prefixes, or
  dark cards merely to unify unrelated interfaces.

## Window and Layout

- Preserve the `OSDCloud` title, centered startup, initial 800-by-700-DIP
  dimensions, and `CanResizeWithGrip` behavior.
- Treat sizes as device-independent pixels, not screenshot coordinates.
  Preserve the root margin `10,0,10,10` and existing `Auto`, `Auto`, `5`, `380`,
  `5`, `*` row structure unless the requested layout change requires adjustment.
- Preserve the visual hierarchy:
  1. Top menu: **Logs**, **WMI**, **Shell**, and **Privacy**.
  2. Upper **Device** and **Identity** tabs.
  3. **Deployment Settings** tab with a scrollable settings grid.
  4. Bottom logo on the left and **Start** on the right.
- Keep device information readable: manufacturer, model, product, SKU, BIOS,
  TPM, and Autopilot details. Identity values retain serial number, UUID,
  and conditional hardware-hash presentation.
- Keep menu height at 30 DIPs, its border thickness at zero, and item padding
  at 4 DIPs. Tabs use 1-DIP borders, 6-DIP margin/padding, and bold tab headers;
  white surfaces do not mean every container has the same border treatment.
- Match the Device grid's `110`, `160`, `10`, `110`, `*` columns and compact
  20-DIP rows. Settings use `120`, `180`, `20`, `70`, `180`, `*` columns,
  generally 4-DIP control margins, and 24-DIP semibold ComboBoxes. The current
  default XAML does not declare control `MinHeight` values.
- Keep scrolling inside the deployment settings region. Long labels, catalog
  names, task summaries, and driver-pack values must not cover the Start button
  or force essential settings out of reach.
- Preserve label/selector alignment, neighboring control margins, and tab order
  when adding a row. Change grid row assignments as well as child order.
- Keep the bottom action grid's 4-DIP margin and `*`, `Auto` columns so the
  logo and Start remain separate from the scrolling settings.
- Do not turn deployment configuration into builder-style navigation cards.
  This is selection followed by explicit deployment confirmation.

## Settings and Dynamic Content

Preserve these named controls and their existing event/data contracts:

| Control | Purpose |
|---|---|
| `TaskSequenceCombo` | Workflow task selection and summary |
| `OperatingSystemCombo` | Catalog-backed OS selection |
| `OSLanguageCodeCombo` | OS language |
| `OSEditionCombo` | Edition |
| `OSActivationCombo` | Retail/Volume activation |
| `DriverPackCombo` | Driver-pack selection |

- Populate choices from the existing workflow and catalogs, not hard-coded
  sample values. Keep display text distinct from underlying catalog identity.
- Preserve dependent-selector refresh and state updates. An OS change affects
  the catalog object, language, image filename/cache information, and activation
  constraints; it is not just a label update.
- Keep task summaries synchronized with the selected workflow task.
- Preserve blank/null-selection normalization and explicit errors for missing
  catalog matches. A styling change must not select an arbitrary replacement
  OS just to keep the window looking populated.
- Keep edition-specific activation behavior: Home forces Retail; Enterprise
  forces Volume and disables activation selection; Pro/Education retain the
  available activation choice.
- Workflow runtime parameters and command-line disk customization do not
  automatically imply GUI controls. Do not add disk selectors or change the
  public parameter surface as an incidental styling change.

## Menus, Accessibility, and Safeguards

- Preserve Logs/WMI menu rebuilding from the runtime log directory, file
  existence checks, and warning/error dialogs for unavailable files.
- Keep CMD and Windows PowerShell shell actions. Show PowerShell 7 only when
  `pwsh.exe` is available; preserve the Privacy action.
- Preserve identity tooltips and click-to-copy behavior for serial, UUID, and
  hardware hash, including existing clipboard retry handling.
- The default XAML does not have BootMenu's extensive automation metadata.
  For new or modified interactive controls, use meaningful accessible names,
  logical tab order, and visible keyboard focus without claiming those
  properties are already implemented throughout the window.
- Keep native disabled-state feedback and explain unavailability using existing
  text/tooltips. Do not rely on color alone to communicate a restriction.
- Start remains disabled until there is a valid operating-system catalog object.
  Visual polish must not bypass selection validity or activation constraints.
- Preserve the Start confirmation handoff: the window sets its dialog result
  and confirmation state, then closes; the GUI wrapper starts workflow execution
  only after confirmation.
- Close/cancel is not confirmation. It must not start deployment, set deployment
  start timing, or produce a success-shaped fallback.
- Preserve CLI/GUI dispatch, licensing and incognito behavior, parameter
  forwarding, initialization failures, and reporting semantics. UI selection
  time stays excluded from deployment execution timing.
- Never run disk preparation, workflow tasks, downloads, shell launches, or
  real deployment to verify a control's appearance.

## Implementation Workflow

1. Resolve the requested workflow and its actual UI entry point. Determine
   whether the change belongs in the default UX or a workflow override.
2. Read XAML alongside PowerShell population and event handlers. Check control
   names, grid rows, visibility, selection state, and action enablement.
3. Apply the smallest coherent change using existing WPF patterns. Preserve
   bindings, handler contracts, runtime asset resolution, and override fallback.
4. Update directly related tests and documentation when behavior changes.
   Do not add theme dependencies or a shared style abstraction solely to
   document the current interface.
5. For PowerShell changes, parse changed scripts and run the relevant existing
   tests from the repository root:

   ```powershell
   Invoke-Pester -Path .\OSDCloud\public\WinOS\Deploy-OSDCloud.Tests.ps1,
       .\OSDCloud\private\Initialize-DeployOSDCloud.Tests.ps1
   ```

6. For XAML changes, verify that the markup loads in WPF, then inspect the
   real window with synthetic catalog/device data and mocked external actions.
   These behavior tests mock the UI; passing them does not establish visual
   correctness. Do not launch the public deployment command as a preview.

## Acceptance Scenarios

- Inspect the default window at its initial size and while resizing. Verify
  tab content, scrolling, logo scaling, and reachable Start action.
- Test long localized language/edition names, task summaries, driver-pack
  descriptions, and identity values without clipping essential information.
- Change OS, edition, activation, task, language, and driver pack; verify
  dependent values, summaries, and selected state remain synchronized.
- Confirm Home/Enterprise activation restrictions and invalid/empty catalog
  handling. Start must remain disabled when no valid OS object exists.
- Exercise keyboard navigation, identity copying, unavailable logs, and hidden
  PowerShell 7 using mocks; verify explicit feedback and preserved focus.
- Verify confirmation and close/cancel separately without executing deployment.
  Check both an active workflow UI override and default fallback when changing
  shared UI resolution or GUI handoff code.
