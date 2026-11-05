---
name: osdcloudbootmenu-style
description: 'Apply the OSDCloud BootMenu WPF visual style. Use whenever adding, editing, or reviewing Invoke-OSDCloudBootMenu profile selection, Keyboard Layout, OSDCloud Explorer navigation, window chrome, cards, icons, typography, colors, buttons, lists, spacing, resizing, keyboard focus, or accessibility. Covers the runtime BootMenu, not Invoke-OSDCloudBoot image-building pages or Deploy-OSDCloud deployment settings.'
---

# OSDCloud BootMenu Style

## Scope and References

Keep the dark, Windows Settings-inspired runtime profile selector consistent.
Use its existing WPF window and local shared resources; do not introduce a web
UI, WinUI, external theme, icon package, or new dependency.

- Public entry point: [Invoke-OSDCloudBootMenu.ps1](../../../OSDCloud/core/modules/OSDCloudBootMenu/public/Invoke-OSDCloudBootMenu.ps1)
- Executable inline XAML, resources, dynamic controls, and events:
  [Show-OSDCloudBootMenuProfileWindow.ps1](../../../OSDCloud/core/modules/OSDCloudBootMenu/private/Show-OSDCloudBootMenuProfileWindow.ps1)
- Runtime behavior tests: [Invoke-OSDCloudBootMenu.Tests.ps1](../../../OSDCloud/core/modules/OSDCloudBootMenu/public/Invoke-OSDCloudBootMenu.Tests.ps1)
- Profile schema and command lifecycle:
  [osdcloudbootmenu-profile-json](../osdcloudbootmenu-profile-json/SKILL.md)

Read the relevant executable XAML and event handlers before changing appearance.
The public command orchestrates startup and selected-profile execution; the
private window owns presentation. A request to document style does not authorize
restyling the interface.

This is not the OSDCloud Boot image builder. Do not copy its Home card heights,
Build/Task prefixes, Build button, workspace selectors, or branding layout into
BootMenu. It is also not the light, workflow-specific Deploy-OSDCloud settings
window. Use the profile JSON skill when changing profile schema or semantics,
rather than treating that work as styling.

## Shared Visual Language

Reuse the window's named resources rather than duplicating color literals or
creating near-identical local styles. The executable resources remain the
authority if the theme is deliberately changed.

| Role/resource | Color |
|---|---|
| Window background | `#161F5B` |
| `SurfaceBrush` - cards | `#1C2868` |
| `ControlBrush` - controls | `#243475` |
| `SidebarBrush` - navigation | `#111949` |
| `BorderBrush` - control outlines | `#53639C` |
| `HoverBrush` - hover feedback | `#2D4088` |
| `SelectionBrush` - list selection | `#1F50A5` |
| `AccentBrush` - icons and focus | `#31D1FF` |
| `SecondaryTextBrush` - supporting text | `#CDD9F3` |
| Primary text | `#F5F5F5` |

- Preserve the `Segoe UI Variable Text, Segoe UI` font stack and 13-DIP body
  text. Measurements are device-independent pixels, not screenshot pixels.
- Use `CardTitleStyle` for 16-DIP semibold headings with a 24-DIP line height.
  Keep title, supporting text, and selection state visually distinct.
- Use `IconStyle` with `Segoe Fluent Icons, Segoe MDL2 Assets`, 20-DIP size,
  and accent foreground. Sidebar icons use their compact 18-DIP treatment
  and 20-DIP line box.
- Use font glyphs, not emoji, bitmap substitutes, or an external icon library.
  Preserve the existing footer logo at 40 DIPs high with uniform scaling and
  a 12-DIP right margin; do not replace the shell with the builder's branding.
- Keep layout rounding and device-pixel snapping enabled.

## Window and Navigation

- Preserve the title `Recast Software - OSDCloud BootMenu`, centered startup,
  and topmost behavior. Initial size is 640 by 480 DIPs; minimum size is
  480 by 360 DIPs before work-area clamping. Retain the runtime clamping and
  monitor/DPI-aware maximize correction so the window stays within the usable
  desktop rather than covering the taskbar.
- Retain the custom `WindowChrome`: 48-DIP caption height, no glass frame,
  system resize border, and no Aero caption buttons.
- Keep the custom pane toggle, minimize, maximize/restore, and close actions
  wired to their current window behavior. Do not replace these with decorative
  glyphs or interfere with dragging and resizing.
- Preserve the two-column sidebar/content shell and title bar spanning both
  columns. The pane starts compact at 56 DIPs and expands to 200 DIPs.
  Keep the sidebar vertically scrollable and its compact mode usable.
- Keep the existing navigation entries and semantics: **Profiles**,
  **Keyboard Layout**, and **OSDCloud Explorer**. Explorer is a separate launch,
  not a profile selection or a deployment action.
- Navigation remains single-select. Preserve the muted selected surface,
  3-DIP accent indicator, 6-DIP row corners, hover feedback, and keyboard focus.
  Use `SidebarNavigationItemStyle`, `SidebarNavigationIconStyle`,
  `SidebarLabelStyle`, and `SidebarButtonStyle`. Compact mode hides labels,
  centers icons, uses `4,8,4,8` padding, and supplies label tooltips; expanded
  mode restores labels, alignment, margins, and 8-DIP padding. Update the pane
  toggle's tooltip and accessible name with its state.
- Keep content margins at `36,24`, the page icon column at 36 DIPs, and the
  text/list column flexible. Profile and keyboard pages use `Auto`, `*`, `Auto`
  rows so lists grow while headings/actions remain reachable. Preserve the
  sidebar-colored footer, top border, and `16,10` padding.
- Use flexible content sizing and internal list scrolling so the selected
  profile, its description, and actions remain usable at the minimum size.
  Do not force the image builder's large window or 200-DIP sidebar onto this UI.

## Cards, Lists, and Actions

- Use `CardStyle` with `SurfaceBrush`, 4-DIP corners, and 16-DIP padding.
  Keep its zero-thickness border instead of borrowing another window's template.
- Retain the Profiles page hierarchy: icon and heading, explanatory text,
  scrollable profile selection, and **Start** action.
- Profile rows use 4-DIP corners, separate hover and selected backgrounds,
  and an accent keyboard-focus border. Selected and focused are different
  states; preserve feedback for both.
- Keep the profile list single-select. Render display names and descriptions
  from profile data rather than replacing them with folder names or synthetic
  Build/Task labels.
- Keep the Keyboard Layout page's selection and application controls distinct
  from profile Start. Choosing a keyboard layout must not start a profile.
- Reuse existing button templates: hand cursor, 4-DIP corners, hover/pressed
  feedback, visible keyboard focus, and reduced disabled opacity.
  Keep `TitleBarButtonStyle`, `TitleBarCloseButtonStyle`, and
  `TitleBarFocusVisualStyle` for chrome rather than styling it as page content.
- Preserve themed scrollbars, including rounded 4-DIP thumbs and accent
  hover/drag feedback through `ScrollBarThumbStyle` and
  `ScrollBarPageButtonStyle`. Lists must scroll without hiding page actions.
- Retain the existing glyph vocabulary: Profiles `E77B`, Keyboard Layout
  `E765`, Explorer `EC50`, pane toggle `E700`, minimize `E921`, maximize `E922`,
  restore `E923`, and close `E8BB`.

## Accessibility and Behavior

- Maintain accurate `AutomationProperties.Name` and `HelpText` on the window,
  navigation, title-bar buttons, profile controls, and keyboard controls.
  Update accessible names with visible label changes.
- Preserve tooltips, logical tab order, visible focus, and keyboard operation
  in both expanded and compact navigation. Color alone must not convey state.
- Keep Start disabled until a profile is selected. Preserve its conditional
  `IsDefault` behavior; Enter must not accidentally start a profile from an
  unrelated page or control.
- Preserve profile double-click selection and Escape/close cancellation.
  Start/double-click return the original candidate object stored in the list
  item's `Tag`, not display text. Cancellation returns `$null` and must not
  become a default deployment or implicit selection.
- Load keyboard layouts lazily on the keyboard page. Preserve initial-selection
  suppression and the 300-ms dispatcher timer that coalesces arrow-key browsing.
  Selecting the current layout updates status without applying it again.
  Keep current-layout labels/automation names and explicit failure status.
- Stop the keyboard timer when the window closes. Do not let a cosmetic change
  introduce duplicate handlers or delayed updates against a closed window.
  Preserve test mode, which reports the intended keyboard command without
  applying it, and keep Start non-default while browsing keyboard layouts.
- Keep Explorer launch and cleanup paths intact; surface failures through
  existing error/status behavior rather than silently ignoring them.
- Do not alter profile discovery, zero/one/multiple-profile routing, CLI
  selection, startup phases, module updates, licensing, or selected-profile
  execution as a side effect of appearance changes.
- Never execute stored profile commands, import packs, startup scripts, or a
  deployment just to demonstrate a visual state.

## Implementation Workflow

1. Locate the affected page and its resources in the private window function.
   Read the corresponding event wiring and public-command handoff.
2. Check both XAML and programmatic updates for labels, glyphs, tooltips,
   automation names, visibility, selection, and default-button state.
3. Make the smallest coherent change using existing resources. Preserve
   control names and handler contracts unless a behavior change is requested.
4. Update directly related tests and user documentation when behavior changes.
   Keep profile schema work separate from visual work.
5. For PowerShell changes, parse changed scripts and run the focused existing
   Pester tests from the repository root:

   ```powershell
   Invoke-Pester -Path .\OSDCloud\core\modules\OSDCloudBootMenu
   ```

6. Inspect the real WPF window using inert profile data and mocked external
   actions. The runtime tests mock the window; they do not prove rendered
   layout. Do not invoke the public startup command merely to show the UI.
   The standalone module imports its commands on full Windows, but the runtime
   Invoke command still refuses startup outside WinPE. Import its manifest
   explicitly; use Test-OSDCloudBootMenu for the inert preview.

## Acceptance Scenarios

- Resize at 640 by 480 and 480 by 360 DIPs, then maximize/restore. Verify
  readable headings, scrollable lists, reachable actions, and functional chrome.
- Toggle expanded/compact navigation, use Tab and keyboard selection, and
  verify the selected page and visible focus remain understandable.
- Test short, long, and wrapped profile names/descriptions. Verify selection,
  hover, focus, and disabled Start without clipping or shifting content.
- Confirm selection, double-click, Enter, Escape, and close return the same
  results as before; no stored commands execute during these checks.
- Change keyboard layout, close while its delayed update is pending, and
  verify cleanup. Mock Explorer launch and verify it does not select a profile.
