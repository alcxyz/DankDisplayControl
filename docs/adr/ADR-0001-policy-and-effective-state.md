# ADR-0001: Keep selected policy separate from effective display state

## Status

Accepted

## Context

A persisted display policy does not fully describe what a user can currently
see. Hotplug, display power, adaptive fallback, and an armed mirror request can
all make the effective compositor state differ from the selected policy.

## Decision

The plugin reads the selected layout and mirror request from the stable couch
command contract, but reads effective outputs and mirror clients directly from
Hyprland. The UI always presents these as separate pieces of state.

Display roles are derived from physical dimensions at runtime. Hardware model,
serial, and connector identifiers are not stored by the plugin.

## Consequences

- The bar can tell the user what is actually active without duplicating the
  host's policy engine.
- An enabled mirror request is shown as **Armed** until native mirroring or the
  supervised mirror client is observable.
- The plugin remains a presentation layer; layout application and workspace
  movement stay in host configuration.
