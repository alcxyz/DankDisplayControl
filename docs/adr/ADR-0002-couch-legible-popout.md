# ADR-0002: Use a couch-legible state/action/policy hierarchy

## Status

Accepted

## Context

DMS can scale typography for television viewing, but simply doubling text in a
desktop-width popout causes labels, state, and buttons to compete for horizontal
space. Display control also has three distinct concepts that should not blur
together: what is active now, immediate actions, and the selected layout policy.

## Decision

Use a wider DMS-native popout with three explicit zones:

1. **Now showing** presents effective Hyprland outputs.
2. **Quick actions** provides full-row mirror and audio targets.
3. **Layout policy** presents the persisted policy as a uniform two-column
   choice grid.

No text label shares a narrow horizontal band with a conventional button.
Output details use short television-oriented resolution labels, and state is
reinforced with both text and theme color. The whole action row is clickable so
phone pointers and couch input do not require precision aiming.

## Consequences

- The normal three-display state fits on a 1080p output at DMS font scale 2.0.
- Selected policy remains visually distinct from effective state.
- The popout consumes more horizontal space than a typical desktop widget.
- Future actions should use the same full-row interaction pattern rather than
  adding compact button islands.
