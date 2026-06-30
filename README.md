# HostAppSwiftNio

A SwiftUI app backed by an embedded SwiftNIO mock server. The app fetches products from a local API endpoint and renders a book list, while the browser control panel allows live editing of the `/api/products` JSON response and status code.

## Overview

- `HostAppSwiftNio/` contains the app source and embedded mock server.
- `HostAppSwiftNioTests/` contains unit tests.
- `HostAppSwiftNioUITests/` contains UI tests.
- `Package.swift` defines the Swift package and SwiftNIO dependencies.

## Project structure

```
Package.swift
Package.resolved
README.md
HostAppSwiftNio/
  Book.swift
  BookData.swift
  BookDetailView.swift
  BookListView.swift
  BookService.swift
  ContentView.swift
  HostAppSwiftNioApp.swift
  MockServer.swift
  Assets.xcassets/
  Resources/
    index.html
HostAppSwiftNio.xcodeproj/
HostAppSwiftNioTests/
  HostAppSwiftNioTests.swift
HostAppSwiftNioUITests/
  HostAppSwiftNioUITests.swift
  HostAppSwiftNioUITestsLaunchTests.swift
```

## Key files

- `HostAppSwiftNio/MockServer.swift` - Implements the embedded SwiftNIO HTTP server and browser control panel.
- `HostAppSwiftNio/BookService.swift` - Fetches `/api/products` from the local mock server.
- `HostAppSwiftNio/BookListView.swift` - Displays the book list and handles error states.
- `HostAppSwiftNio/HostAppSwiftNioApp.swift` - Starts the mock server when the app launches.

## Running the app

1. Open `HostAppSwiftNio.xcodeproj` in Xcode.
2. Build and run the app on a simulator or device.
3. The mock server starts automatically on `http://127.0.0.1:8080`.
4. Open `http://127.0.0.1:8080/products` in a browser to access the control panel.

## Notes

- The browser panel edits the response for `/api/products`.
- Refresh the mobile app list to see JSON updates from the mock server.
