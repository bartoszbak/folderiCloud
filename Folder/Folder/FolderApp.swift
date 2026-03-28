//
//  FolderApp.swift
//  Folder
//
//  Created by Bart Bak on 26/03/2026.
//

import SwiftUI

@main
struct FolderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var auth = WordPressAuthManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(auth)
                .fontDesign(.rounded)
        }
    }
}
