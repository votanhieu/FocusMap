//
//  AppDelegate.swift
//  FocusMap
//
//  Created by Hieu on 5/12/25.
//

import UIKit

// MARK: - AppDelegate

/// Application delegate handling app lifecycle events and configuration
/// Responsible for app initialization, state transitions, and resource management
@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    // MARK: - Properties
    
    /// The root window of the application
    var window: UIWindow?
    
    // MARK: - Application Lifecycle Methods
    
    /// Called when the application has finished launching
    /// This is the entry point for app-specific initialization after system setup
    /// - Parameters:
    ///   - application: The singleton app object
    ///   - launchOptions: Dictionary with launch-specific information (URLs, notifications, etc.)
    /// - Returns: Boolean indicating if the app launch should continue
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Override point for customization after application launch
        // Add app initialization code here (e.g., analytics setup, theme configuration, etc.)
        return true
    }
    
    /// Called when the application transitions from active to inactive state
    /// This occurs for temporary interruptions (incoming call, SMS) or when user exits the app
    /// Use this method to pause ongoing tasks, disable timers, and stop animations
    /// - Parameter application: The singleton app object
    func applicationWillResignActive(_ application: UIApplication) {
        // Pause any ongoing gameplay or time-sensitive operations
        // Save any unsaved user data
        // Stop background sounds or animations
    }
    
    /// Called when the application enters the background
    /// The app may be suspended after this method returns
    /// Use this method to:
    /// - Release shared resources
    /// - Save user data and application state
    /// - Invalidate timers and file handles
    /// - Store app state for later restoration
    /// - Parameter application: The singleton app object
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Save current plane mappings (already done in GameViewController via UserDefaults)
        // Close any open resources or connections
        // Prepare app for potential termination
    }
    
    /// Called when the application transitions from background to foreground
    /// Use this method to undo changes made when entering background
    /// - Parameter application: The singleton app object
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Restore app state from background
        // Resume any paused operations
        // Refresh any resources that were released
    }
    
    /// Called when the application becomes active after being inactive
    /// Restart any tasks that were paused while the app was inactive
    /// This is called after:
    /// - App launch completion
    /// - Return from background
    /// - User dismisses incoming notifications/calls
    /// - Parameter application: The singleton app object
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Resume gameplay and animations
        // Refresh UI with latest data
        // Restart any paused timers or background tasks
        // Resume any interrupted operations
    }
}
