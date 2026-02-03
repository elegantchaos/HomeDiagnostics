# HomeKit Service Plan

This document describes the planned XPC-based HomeKit helper app that enables a CLI to access HomeKit in a supported, entitlement-safe way.

## Goals

- Provide HomeKit authorization and access in a signed, UI-capable host.
- Expose a minimal, stable XPC API that the CLI can call.
- Keep the app bundle small and focused on HomeKit brokering.
- Support incremental expansion without breaking CLI callers.

## Project Layout

- App and XPC service code: `Sources/HomeKitService`
- Tests: `Tests/HomeKitService`

## Architecture Overview

- **HomeKitService app bundle**
  - SwiftUI app target with HomeKit capability enabled.
  - Owns HomeKit authorization flow and holds entitlements.
  - Hosts an embedded XPC service for CLI requests.

- **XPC service**
  - Defines an `@objc` protocol with async methods.
  - Converts HomeKit objects into simple DTOs for the CLI.
  - Returns structured errors for authorization or availability issues.

- **CLI client**
  - Connects to XPC service.
  - Maps subcommands to XPC methods.

## XPC Protocol (Initial Scope)

### Authorization Flow

- `requestAuthorization()`
  - Triggers HomeKit permission prompt.
  - Returns current authorization status.

- `authorizationStatus()`
  - Returns cached authorization state without prompting.

### Minimal HomeKit API (Current HomeDiagnostics Usage)

- `fetchHomes()`
- `fetchAccessories(homeID:)`
- `fetchCharacteristics(accessoryID:)`
- `readValue(characteristicID:)`
- `writeValue(characteristicID:value:)`

## Data Contracts

- Use plain Swift structs for DTOs.
- Prefer stable identifiers (UUIDs or persistent HomeKit identifiers).
- Encode results using `Codable` for transport safety.

## Error Strategy

- Define a small error enum for:
  - Not authorized
  - HomeKit unavailable
  - Accessory/characteristic not found
  - Underlying HomeKit errors
- Surface errors in a CLI-friendly format.

## Security and Entitlements

- HomeKit entitlement enabled on the app target.
- XPC service embedded in the app bundle.
- CLI remains unsigned and only communicates with the service.
- The app is signed with development credentials for internal use.

## Expansion Plan

- Add higher-level APIs for scenes, triggers, and home configuration.
- Support bulk reads and writes for improved CLI performance.
- Add event streaming for live updates.
- Add diagnostics and audit logging (opt-in).

## Testing Plan

- Unit tests for DTO conversion and XPC boundary types.
- Unit tests for authorization state handling.
- Integration tests using a mocked HomeKit layer.
- Manual testing checklist for first-run authorization.
