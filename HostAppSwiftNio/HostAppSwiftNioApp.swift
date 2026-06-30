//
//  HostAppSwiftNioApp.swift
//  HostAppSwiftNio
//
//  Created by Mehta on 29/06/26.
//

import SwiftUI

@main
struct HostAppSwiftNioApp: App {
    private let mockServer = MockServer()

    init() {
        mockServer.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    mockServer.start()
                }
        }
    }
}
