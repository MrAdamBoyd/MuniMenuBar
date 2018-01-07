//
//  AppDelegate.swift
//  TransitBar
//
//  Created by Adam Boyd on 2016-10-11.
//  Copyright © 2016 adam. All rights reserved.
//

import Cocoa
import SwiftBus
#if SPARKLE
import Sparkle
#endif
import Fabric
import Crashlytics
import CoreLocation
import MapKit

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate, TransitManagerDelegate {
    
    //Item that lives in the status bar
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    /// This is the icon when there is nothing to show in the menubar
    private var emptyStatusBarTemplateImage: NSImage {
        let image = #imageLiteral(resourceName: "TemplateIcon")
        image.isTemplate = true
        return image
    }
    
    private let storyboard = NSStoryboard(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
    private var listWindowController: NSWindowController?
    private var aboutWindowController: NSWindowController?
    private var alertsWindowController: NSWindowController?
    private var notificationsWindowController: NSWindowController?
    
    private let transitManager = TransitManager()
    private lazy var statusBarManager = StatusBarManager(statusItem: self.statusItem, dataController: DataController.shared, delegate: self)
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        //Fabric
        Fabric.with([Crashlytics.self])
        
        //See https://docs.fabric.io/apple/crashlytics/os-x.html
        UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
        
        
        //Setting up the status bar menu and the actions from that
        self.statusItem.image = self.emptyStatusBarTemplateImage
        self.createMenuItems()
        //TODO: this
//        self.statusBarManager.setUpMenuItem()
        
        //Setting up transit manager
        self.transitManager.delegate = self
        self.transitManager.loadData()
        
        
        #if SPARKLE
            //Setting up the Sparkle updater
            SUUpdater.shared().automaticallyChecksForUpdates = true
        #endif
        
        self.transitManager.determineTrackingLocation()
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.createMenuItems), name: .entriesChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.determineTrackingLocation), name: .displayWalkingTimeChanged, object: nil)
        
        if DataController.shared.savedEntries.isEmpty {
            self.openSettingsWindow()
        }
        
        NSUserNotificationCenter.default.delegate = self
        
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        
    }
    
    @objc
    func determineTrackingLocation() {
        self.transitManager.determineTrackingLocation()
    }
    
    /// Creates the menu item from scratch
    @objc
    func createMenuItems() {
        if self.statusItem.menu == nil {
            self.statusItem.menu = NSMenu()
        }
        
        self.statusItem.menu?.removeAllItems()
        
        for (index, entry) in DataController.shared.savedEntries.enumerated() {
            //When clicking on the menu, all the stops always show
            let title = "\(entry.stop.routeTitle) -> \(entry.stop.direction)"
            
            self.statusItem.menu?.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
            
            if DataController.shared.displayWalkingTime {
                
                self.statusItem.menu?.addItem(NSMenuItem(title: self.locationTextFrom(source: self.transitManager.currentLocation, to: CLLocation(latitude: entry.stop.lat, longitude: entry.stop.lon)), action: nil, keyEquivalent: ""))
                self.setWalkingTimeForMenuItemWith(entry: entry, at: index) //Async gets the walking time
            }
            
            self.statusItem.menu?.addItem(NSMenuItem(title: "Set Notification", action: #selector(self.userWantsToSetNotificationFor(_:)), keyEquivalent: ""))
            
            self.statusItem.menu?.addItem(NSMenuItem.separator())
            
        }
        
        self.statusItem.menu?.addItem(NSMenuItem(title: "About TransitBar", action: #selector(self.openAboutWindow), keyEquivalent: ""))
        #if SPARKLE
            self.statusItem.menu?.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(self.checkForUpdates), keyEquivalent: ""))
        #endif
        self.statusItem.menu?.addItem(NSMenuItem.separator())
        self.statusItem.menu?.addItem(NSMenuItem(title: "View Alerts", action: #selector(self.openAlertsWindow), keyEquivalent: ""))
        self.statusItem.menu?.addItem(NSMenuItem(title: "View Scheduled Notifications", action: #selector(self.openNotificationsWindow), keyEquivalent: ""))
        self.statusItem.menu?.addItem(NSMenuItem(title: "Preferences...", action: #selector(self.openSettingsWindow), keyEquivalent: ","))
        self.statusItem.menu?.addItem(NSMenuItem(title: "Quit", action: #selector(self.terminate), keyEquivalent: "q"))
        
        self.transitManager.loadData()
        self.updateMenuItems()
    }
    
    /// Creates the menu items for preferences/about/etc and also for all the transit entries
    func updateMenuItems() {
        var menuText = ""
        
        for (index, entry) in DataController.shared.savedEntries.enumerated() {
            
            //Creating the text that will be for this stop in the menubar
            var menuTextForThisEntry = entry.stop.routeTag + ": "
            //Creating the text that will be shown when you click on this item
            var insideDropdownTitle = "\(entry.stop.routeTitle) @ \(entry.stop.stopTitle) -> \(entry.stop.direction)"
            var addingPredictionsForInsideDropdown = ": "
            
            if let error = entry.error {
                
                //Show the error to the user
                //Need to add comma and space after as characters are normally removed before being shown
                menuTextForThisEntry.append("Error, ")
                addingPredictionsForInsideDropdown.append("Error: \(error.localizedDescription), ")
                
            } else if let predictions = entry.stop.predictions[entry.stop.direction] {
                
                //Set up the predictions text
                for (index, prediction) in predictions.enumerated() {
                    
                    if index < DataController.shared.numberOfPredictionsToShow {
                        //Only add however many predictions the user wants
                        menuTextForThisEntry.append("\(prediction.predictionInMinutes), ")
                    }
                    
                    addingPredictionsForInsideDropdown.append("\(prediction.predictionInMinutes), ")
                }
                
                self.checkForNotificationsToSend(for: entry, predictions: predictions)
                
            }
            
            //Only show it in the menubar if it should be shown based on current time
            if entry.shouldBeShownInMenuBar {
                menuTextForThisEntry = String(menuTextForThisEntry.dropLast(2)) + "; " //Remove last comma and space and add semicolon
                menuText.append(menuTextForThisEntry)
            }
            
            //Remove comma and space
            addingPredictionsForInsideDropdown = String(addingPredictionsForInsideDropdown.dropLast(2))
            
            //If there are no predictions, add a dash
            if addingPredictionsForInsideDropdown == ": " {
                addingPredictionsForInsideDropdown.append("--")
            }
            
            insideDropdownTitle.append(addingPredictionsForInsideDropdown)
            
            DispatchQueue.main.async {
                if let menuItemToUpdate = self.statusItem.menu?.items[self.menuItemIndexForEntryIndex(index)] {
                    menuItemToUpdate.title = insideDropdownTitle
                }
            }
            
        }
        
        //At the very end, set the status bar text
        DispatchQueue.main.async { self.setStatusBarText(menuText) }

    }
    
    /// Checks if this entry has notifications waiting, and if it matches all conditions, sends the notification
    ///
    /// - Parameter entry: entry to look at
    /// - Parameter predictions: predictions for this entry
    private func checkForNotificationsToSend(for entry: TransitEntry, predictions: [TransitPrediction]) {
        //Check for notifications here
        for (index, notification) in DataController.shared.scheduledNotifications.enumerated() {
            
            //Notification is for this item
            if notification.entry.stop.stopTag == entry.stop.stopTag && notification.entry.stop.routeTag == entry.stop.routeTag {
                
                //This filter call leaves in predictions that are less than or equal to the notification's minutes and greater than 5 - the notification's minutes. If this is nonnil, we should send the user a notification
                let firstValid = predictions.first(where: { $0.predictionInMinutes <= notification.minutesForFirstPredicion && $0.predictionInMinutes > notification.minutesForFirstPredicion - 5 })
                
                if let firstValid = firstValid {
                    
                    //Remove this and send notification
                    print("Sending user notification for alert")
                    DataController.shared.scheduledNotifications.remove(at: index)
                    self.sendNotificationFor(notification, firstPredictionInMinutes: firstValid.predictionInMinutes)
                    
                }
            }
        }
    }
    
    /// Determines what the status bar will look like. If there is text to set, uses that text. If no text, uses an image
    ///
    /// - Parameter text: text to set
    fileprivate func setStatusBarText(_ text: String) {
        //If there is no menubar text, add two dashes
        if text.isEmpty {
            self.statusItem.title = ""
            if self.statusItem.image == nil {
                self.statusItem.image = self.emptyStatusBarTemplateImage
            }
        } else {
            self.statusItem.title = String(text.dropLast(2)) //Remove final ; and space
            if self.statusItem.image != nil {
                self.statusItem.image = nil
            }
        }
    }
    
    /// The index of the menu item for the entry index (2nd entry would be the 6th menu item)
    ///
    /// - Parameter index: index of the entry
    /// - Returns: index in the menu
    func menuItemIndexForEntryIndex(_ index: Int) -> Int {
        if DataController.shared.displayWalkingTime {
            return index * 4
        } else {
            return index * 3
        }
    }
    
    /// Gets the entry for the specified menu item index
    ///
    /// - Parameter index: index of the menu item
    /// - Returns: Entry at the index
    func entryForMenuIndex(_ index: Int) -> TransitEntry {
        if DataController.shared.displayWalkingTime {
            return DataController.shared.savedEntries[index / 4]
        } else {
            return DataController.shared.savedEntries[index / 3]
        }
    }
    
    /// Builds the string for the menu item that contains the distance and walking time to that stop
    ///
    /// - Parameters:
    ///   - source: user's location
    ///   - destination: stop's location
    ///   - overrideDistance: use this distance instead of calculating
    ///   - walkingTime: include the walking time to format this
    /// - Returns: formatted string
    func locationTextFrom(source: CLLocation?, to destination: CLLocation?, overrideDistance: CLLocationDistance? = nil, walkingTime: TimeInterval? = nil) -> String {
        
        var returnString = ""
        
        if let distance = overrideDistance {
            //Use this distance instead of calculating
            
            returnString = "Distance: \(self.formatDistance(distance))"
            
        } else if let location = source, let destinationLocation = destination {
            
            //Get the actual distance to the location
            let distance = location.distance(from: destinationLocation)
            
            returnString = "Distance: \(self.formatDistance(distance))"
            
        } else {
            
            //Unknown distance
            returnString = "Distance: unknown"
        }
        
        if let walkingTime = walkingTime {
            let toMinutes = Int(round((walkingTime / 60).truncatingRemainder(dividingBy: 60)))
            returnString.append("; walking time: \(toMinutes) minutes")
        }
        
        return returnString
    }
    
    /// Formats distance in the locality that user has set
    ///
    /// - Parameter distance: distance to format
    /// - Returns: formatted string
    func formatDistance(_ distance: CLLocationDistance) -> String {
        //Format the string
        let df = MKDistanceFormatter()
        df.unitStyle = .full
        
        return df.string(fromDistance: abs(distance))
    }
    
    // MARK: - Dealing with locations
    
    /// Gets the walking time for the user's current location to the provided entry. Updates menu item when done
    ///
    /// - Parameters:
    ///   - entry: entry to calculate distance ot
    ///   - index: entry index of the item
    func setWalkingTimeForMenuItemWith(entry: TransitEntry, at index: Int) {
        self.transitManager.directionsRequestFrom(source: self.transitManager.currentLocation, destination: CLLocation(latitude: entry.stop.lat, longitude: entry.stop.lon)) { directionsRequest in
            
            if let directionsRequest = directionsRequest {
                
                let directions = MKDirections(request: directionsRequest)
                directions.calculate() { [unowned self] response, _ in
                    
                    if let routes = response?.routes {
                        
                        //Get the quickest route
                        let quickest = routes.sorted() { $0.expectedTravelTime < $1.expectedTravelTime }[0]
                        
                        //Set the text including the walking time and the actual distance with directions
                        self.statusItem.menu?.items[self.menuItemIndexForEntryIndex(index) + 1].title = self.locationTextFrom(source: nil, to: nil, overrideDistance: quickest.distance, walkingTime: quickest.expectedTravelTime)
                    }
                    
                }
                
            }
        }
    }
    
    // MARK: - Actions
    
    #if SPARKLE
    /**
     Checks Sparkle to see if there are any updates
     */
    @objc
    func checkForUpdates() {
        SUUpdater.shared().checkForUpdates(self)
    }
    #endif
    
    @objc
    func userWantsToSetNotificationFor(_ sender: Any?) {
        guard let item = self.statusItem.menu?.highlightedItem else { return }
        guard let index = self.statusItem.menu?.index(of: item) else { return }
        
        print("User wants to set notification, selected menu item: \(index)")
        let alert = NSAlert()
        alert.messageText = "Enter the number of minutes you'd like to be alerted before the bus or train arrives"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        //Textfield where user will enter the time
        let textField = NSTextField(frame: CGRect(x: 0, y: 0, width: 200, height: 24))
        textField.translatesAutoresizingMaskIntoConstraints = true
        textField.placeholderString = "5"
        alert.accessoryView = textField
        
        if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
            let minutes = textField.integerValue
            if minutes > 0 {
            
                //Valid, create notification
                print("User entered \(minutes) minutes")
                let notification = TransitNotification()
                notification.entry = self.entryForMenuIndex(index)
                notification.minutesForFirstPredicion = minutes
                
                DataController.shared.scheduledNotifications.append(notification)
            
            } else {
                
                //Not valid
                print("User didn't enter a valid number")
                
            }
        } else {
            print("User hit cancel cancel")
        }
    }
    
    /**
     Opens the settings window
     */
    @objc
    func openSettingsWindow() {
        guard let windowController = self.storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "mainWindow")) as? NSWindowController else { return }
        self.listWindowController = windowController
        self.listWindowController?.window?.makeKeyAndOrderFront(self)
    }
    
    /**
     Opens the about window
     */
    @objc
    func openAboutWindow() {
        guard let windowController = self.storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "aboutWindow")) as? NSWindowController else { return }
        self.aboutWindowController = windowController
        self.aboutWindowController?.window?.makeKeyAndOrderFront(self)
    }
    
    /// Opens the window that has all the alerts
    @objc
    func openAlertsWindow() {
        guard let windowController = self.storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "alertsWindow")) as? NSWindowController else { return }
        self.alertsWindowController = windowController
        self.alertsWindowController?.window?.makeKeyAndOrderFront(self)
    }
    
    /// Opens the notification window
    @objc
    func openNotificationsWindow() {
        guard let windowController = self.storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "notificationsWindow")) as? NSWindowController else { return }
        self.notificationsWindowController = windowController
        self.notificationsWindowController?.window?.makeKeyAndOrderFront(self)
    }
    
    /**
     Quits the app
     */
    @objc
    func terminate() {
        NSApplication.shared.terminate(self)
    }
    
    // MARK: - NSUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        //Always return true. Usually notifications are only delivered if application is key. However, this is a menubar application and will never be key.
        return true
    }
    
    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        self.openAlertsWindow()
    }
    
    // MARK: TransitManagerDelegate
    
    func userLocationUpdated(_ newLocation: CLLocation?) {
        self.createMenuItems()
    }
    
    func transitPredictionsUpdated() {
        self.updateMenuItems()
        if let alertsVC = self.alertsWindowController?.contentViewController as? AlertsViewController {
            //If the user has the alerts vc open, reload the messages, as they might have changed
            alertsVC.tableView.reloadData()
        }
    }
    
    /// Sends notifications to the user. This method will send notifications to the user for all the new messages that are not contained in the old messages with high priority.
    ///
    /// - Parameters:
    ///   - newMessages: messages from the most recent prediction
    ///   - oldMessages: messages from the old prediction
    ///   - route: title of the route for notification
    func sendNotificationsToUser(with newMessages: [TransitMessage], differingFrom oldMessages: [TransitMessage], on route: String) {
        
        //Create sets of the message strings for transit messages that have a high priority. They are sets so it is easy to perform diffs.
        let oldMessageSet = Set(oldMessages.filter({ $0.priority == .high }).map({ $0.text }))
        let newMessageSet = Set(newMessages.filter({ $0.priority == .high }).map({ $0.text }))
        
        let messagesToNotify = newMessageSet.subtracting(oldMessageSet)
        
        //Go through each notification and send it
        for message in messagesToNotify {
            let notification = NSUserNotification()
            notification.title = "\(route) Alert"
            notification.informativeText = message
            NSUserNotificationCenter.default.deliver(notification)
        }
    }
    
    /// Sends user notification
    ///
    /// - Parameters:
    ///   - notification: notification to send to user
    ///   - firstPredictionInMinutes: value of the first prediction
    func sendNotificationFor(_ notification: TransitNotification, firstPredictionInMinutes: Int) {
        let userNotification = NSUserNotification()
        userNotification.title = "\(notification.entry.stop.routeTag) Alert"
        userNotification.informativeText = "Your bus or train is coming in \(firstPredictionInMinutes) minutes"
        NSUserNotificationCenter.default.deliver(userNotification)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

}

// MARK: - Status bar

extension AppDelegate: StatusBarManagerDelegate {
    var mostRecentUserLocation: CLLocation? {
        return self.transitManager.currentLocation
    }
    
    func statusBarManager(_ statusBarManager: StatusBarManager, requestDirectionsTo destination: CLLocation?, completion: @escaping (MKDirectionsRequest?) -> Void) {
        self.transitManager.directionsRequestFrom(source: self.transitManager.currentLocation, destination: destination, completion: completion)
    }
    
    func statusBarManager(_ statusBarManager: StatusBarManager, requestsCheckForNotificationsToSendFor entry: TransitEntry, predictions: [TransitPrediction]) {
        self.checkForNotificationsToSend(for: entry, predictions: predictions)
    }
    
    func statusBarManager(_ statusBarManager: StatusBarManager, requestsSetNotificationFor sender: Any) {
        
    }
    
    func statusBarManagerCheckForUpdates(_ statusBarManager: StatusBarManager) {
        SUUpdater.shared().checkForUpdates(self)
    }
    
    func statusBarManagerOpenAboutWindow(_ statusBarManager: StatusBarManager) {
        guard let windowController = self.storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "aboutWindow")) as? NSWindowController else { return }
        self.aboutWindowController = windowController
        self.aboutWindowController?.window?.makeKeyAndOrderFront(self)
    }
    
    func statusBarManagerOpenAlertsWindow(_ statusBarManager: StatusBarManager) {
        guard let windowController = self.storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "alertsWindow")) as? NSWindowController else { return }
        self.alertsWindowController = windowController
        self.alertsWindowController?.window?.makeKeyAndOrderFront(self)
    }
    
    func statusBarManagerOpenNotificationsWindow(_ statusBarManager: StatusBarManager) {
        guard let windowController = self.storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "notificationsWindow")) as? NSWindowController else { return }
        self.notificationsWindowController = windowController
        self.notificationsWindowController?.window?.makeKeyAndOrderFront(self)
    }
    
    func statusBarManagerOpenSettingsWindow(_ statusBarManager: StatusBarManager) {
        guard let windowController = self.storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "mainWindow")) as? NSWindowController else { return }
        self.listWindowController = windowController
        self.listWindowController?.window?.makeKeyAndOrderFront(self)
    }
    
    func statusBarManagerRequestsToTerminate(_ statusBarManager: StatusBarManager) {
        NSApplication.shared.terminate(self)
    }
}
