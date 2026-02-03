# AI coding agent guide (Swift / SwiftUI)

This repository contains one or more apps, tools or libraries written primarily in Swift.
It may only contain Swift Package Manager (SwiftPM) packages.
It may only contain an Xcode project.
It may contain both an Xcode project, and additional code organized into local SwiftPM packages under `Dependencies/`.

The goal of these instructions is to keep contributions modern, safe, and consistent with the project's architecture and Apple platform expectations.

For additional decision-making heuristics and engineering principles, see `Extras/Guidelines/Principles.md`.

## Role & expectations

Act as an expert Swift engineer.

- Follow Apple Human Interface Guidelines and App Review guidelines.
- Prefer minimal, focused changes that match existing style.
- Fix root causes rather than layering workarounds.
- Prefer simple, correct, and maintainable code.


## Platform & language

- Target iOS 26.0+ and/or macOS 26.0+.
- Swift 6.2+.
- Assume strict concurrency checking.
- Assume default actor isolation is enabled.
  - Default to `@MainActor` for UI-facing types.
  - If a type/function is intentionally non-main-actor, state and justify it.


## Architecture

- Any user interface code should be written using SwiftUI.
- SwiftUI views should be backed by testable view models or other non-view logic types.
- Use `@Observable` for shared state. Do not use `ObservableObject`.
- Avoid UIKit/AppKit unless explicitly requested.
- Only add third-party dependencies that are listed in `Extras/Guidelines/Dependencies.md`. Ask first before adding any other dependencies.
- Write cross-platform code where it does not add complexity.


## Project structure & docs

- Use the existing structure and naming conventions (see Package Layering section below).
- Prefer placing code in the appropriate package under `Dependencies/`. Minimize app target code.
- Never add secrets (API keys, tokens) to the repo.

### File naming conventions

- Name files after their primary type: `MyType.swift` contains `struct MyType` or `class MyType`.
- For extensions that add specific functionality, use: `MyType+Functionality.swift` (example: `CommandCentre+HotKeyService.swift`).
- For protocol conformances in separate files, use: `MyType+ProtocolName.swift` (example: `Item+Equatable.swift`).
- Use PascalCase for file names, matching the type name exactly.


## Package layering

This project prefers layering code in SwiftPM packages (under `Dependencies/`) and keeping the main Xcode app targets thin.

Guiding goals:

- Avoid platform-specific code where possible, so lower layers stay broadly reusable.
- Avoid dependencies for code that doesn't need them, so low-level modules remain lightweight.

A common layering pattern is:

- `model` (lowest): data structures, persistence models, IDs, and other broadly reusable types.
- `logic` (middle, optional): business rules, orchestration, and service boundaries; depends on `model`.
- `ui` (highest): SwiftUI views and UI-facing models; depends on `logic` (or directly on `model`).

Packages also help:

- Keep tests close to the code they exercise (package test targets).
- Reduce test build times by rebuilding only affected modules.
- Improve Xcode preview performance by hosting SwiftUI views in packages.


## Swift file Layout

In a swift source file:

- Prefer one type per file; avoid packing multiple types into one file.
- Use nested types when they are tightly coupled to the parent type. 
- Add `///` doc comments for every type, describing its purpose.
- Add `///` doc comments for every property, method, enum case, typealias, etc.
  - Document **all** members, including private ones and those with obvious names.
  - When documenting, provide slightly more context than the name alone conveys.
  - Write comments in natural language that explain the purpose or behavior.
  - For example, instead of "Whether recording" write "Whether the UI is currently recording a hotkey."
  - Even when the intent seems obvious, add doc comments to improve code navigation and generated documentation.
- Add inline comments within the code where intent is not obvious.
- Avoid inline comments that simply repeat what the code already clearly expresses.
- Apply the commenting rules to type extensions as well.
  - Document the extension itself if it adds significant functionality or conformance.
  - Document each member within the extension.
- Place import statements first after the header comment
- Place log channels next if using Logger
- Place the main type definition next
- Place helper types, extensions, and other code next.
- Place #Previews at the bottom, if the type is a SwiftUI view
- Format all source files with `swift format`.
- After a change, run `swift format lint` on all source code and report any problems.


## Swift type layout

When defining a swift class or struct, arrange the code in the following order:

1. stored properties
2. init() definitions
3. computed properties
4. public methods
5. private methods

Additional guidelines:

- Put each protocol conformance into an extension in the same source file if possible.
  - If a type's primary purpose is to conform to a protocol (e.g., `MyView: View`), keep the conformance on the main type declaration.
  - Put additional/supplementary protocol conformances in separate extensions (e.g., `Equatable`, `Hashable`, `Identifiable`).
- Put private methods into an extension in the same source file to visually separate implementation details from the public interface.

When defining an enum, the code should be arranged in the following order:

- cases first
- static methods representing constants next
- computed properties next

When defining a protocol, the code should be arranged in the following order:

- properties
- methods


## General coding guidelines

- Follow the principles in `Extras/Guidelines/Principles.md`.
- Avoid duplication in code and tests.
- Minimize repeated literals (strings, numbers).
- Avoid private single-line var or func wrappers unless the wrapped code is complex or repeated, or the wrapper adds substantial clarity.

## Swift coding guidelines

- Prefer Swift-native APIs over older Foundation or CoreFoundation patterns.
  - Prefer `replacing("a", with: "b")` over `replacingOccurrences(of:with:)`.
  - Prefer `URL.documentsDirectory` and `appending(path:)`.
  - Prefer Swift RegEx over `NSRegularExpression`.
- Formatting:
  - Never use C-style numeric formatting (`String(format:)`) in SwiftUI.
  - Prefer `format:` style formatting (example: `Text(value, format: .number.precision(.fractionLength(2)))`).
- Prefer static member lookup when it improves clarity (example: `.circle`, `.borderedProminent`).
- Concurrency:
  - Never use `DispatchQueue.main.async`.
  - Use Swift concurrency (`Task {}`, `await`, actors) instead.
  - Never use `Task.sleep(nanoseconds:)`; use `Task.sleep(for:)`.
- String filtering based on user input must use `localizedStandardContains()` (not `contains()`).
- Avoid force unwraps and `try!` unless the failure is truly unrecoverable.
- Error handling:
  - Prefer `throws` for synchronous operations that can fail.
  - Prefer `async throws` for asynchronous operations that can fail.
  - Use `Result<Success, Failure>` only when you need to store or pass around success/failure state.
  - Use optional return values for operations where absence of a value is a valid outcome (not an error).
  - Create custom error enums conforming to `Error` for domain-specific failures.
- Classes:
  - Mark classes `final` unless they are explicitly designed for inheritance.
  - Prefer value types (structs, enums) over reference types (classes) unless you need reference semantics.
- Visibility:
  - Assume `internal` is implied; never write it explicitly.
  - Prefer `private` where possible to minimize scope.
  - Use `fileprivate` only when sharing implementation details between types in the same file.
  - Use `public` only for types/members that are part of the module's public API and must be accessible from other modules. 


## SwiftUI guidelines

### Naming

- Suffix general custom views with `View` (example: `MyCustomView`).
- Suffix custom views intended to stand in for a control with the type of that control, eg: `MyCustomButton`, `MyCustomPicker`.
- Suffix custom table or list row views with `Row` (example: `MyCustomRow`).
- Suffix view models with `ViewModel` (example: `MyCustomViewModel`).
- Name protocols with descriptive nouns (example: `CommandCentre`, `HotKeyManager`) or with `-able`/`-ible` suffix for capabilities (example: `Equatable`, `Identifiable`).

### Property wrappers

- Place vars using property wrapper at the top of the view struct, before other stored properties.
- Place environment properties first, then bound parameters, then normal parameters, then internal state. 
- Use `@Environment` to access values from the environment.
- Use `@State` for view-local mutable state that drives the UI.
- Use `@Binding` to create a two-way connection to `@State` owned by a parent view.
- Use `@Observable` for shared state objects instead of `ObservableObject`.
- Prefer `@State private var` for encapsulated view state.
- Use `@Bindable` when you need to create bindings to properties of an `@Observable` object.

### Styling

- Use `foregroundStyle()` not `foregroundColor()`.
- Use `clipShape(.rect(cornerRadius:))` not `cornerRadius()`.

### Navigation

- Always use `NavigationStack`.
- Use `navigationDestination(for:)` for navigation.

### Interactions

- Prefer `Button` over `onTapGesture()` unless tap count/location is required.
- Use the modern `Tab` API; do not use `tabItem()`.
- Never use the 1-parameter `onChange(of:)` variant; use the 0-parameter or 2-parameter variant.

### Layout

- Avoid `UIScreen.main.bounds`.
- Avoid `GeometryReader` when newer alternatives work (example: `containerRelativeFrame()`, `visualEffect()`).
- Avoid hard-coded padding/spacing values unless requested.

### Composition
  - Do not factor views into computed properties; create new `View` structs instead.
  - Avoid `AnyView` unless absolutely required.
- Use opaque return types (`some View`) for view builders and computed view properties.
- Use concrete types only when you need to store views in collections or return different view types conditionally.

### Memory management

- Use `[weak self]` in closures when creating a potential retain cycle with a reference type.
- Use `[unowned self]` only when you can guarantee `self` will outlive the closure.
- For value types (structs), capture semantics are copy-by-default; no need for `weak` or `unowned`.

### Assets

- If a button label uses an icon, include text too: `Button("Title", systemImage: "plus", action: ...)`.
- Prefer `ImageRenderer` over `UIGraphicsImageRenderer`.
- Always add a `#Preview` for every custom `View`.


## SwiftData guidelines

If SwiftData is configured to use CloudKit:

- Never use `@Attribute(.unique)`.
- Model properties must either have default values or be optional.
- All relationships must be optional.


## Building

- After a change to package code, first build just the package target for macOS using `swift build --target <TargetName>` to verify Package.swift dependencies are correct before building the full app.
- After any change, build the app with Xcode checking both macOS and iOS targets for errors.

## Testing

- Always create unit tests for new code.
- Always use Swift Testing, never use XCTest.
- Prefer testing through public/internal interfaces without @testable imports.
- Prefer adding minimal test-only public API to @testable imports, clearly documenting them as "For testing purposes only" or similar.
- Suggest adding unit tests for old code if it is un-tested, or poorly covered.
- Prefer unit tests over UI tests; write UI tests only when unit testing is not feasible.
- Extract shared test helpers when it reduces repetition without obscuring intent.

## Documentation

- Maintain an up to date README.md
- Keep the README short and factual.
- Do not include any "marketing" style copy in the README, such as a "key features" list.
- Include the following sections: Overview, Quick Start, Documentation
- Break out additional information from the README into extra markdown files in Extras/Documentation/.
- Some examples of additional sections that may be appropriate (depending on context): Requirements, Installation, Options, Output Reference, Usage Guide, Performance Guide, Development Guide.
- Create and organise other section documents as appropriate.
- The files in Extras/Guidelines/ are development guidelines; do not modify them.
- Where appropriate, refer to the guideline documents from other documentation. 