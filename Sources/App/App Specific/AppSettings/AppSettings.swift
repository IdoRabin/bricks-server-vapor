//
//  AppSettings.swift
//  Bricks
//
//  Created by Ido Rabin on 24/07/2023.
//  Copyright © 2023 IdoRabin. All rights reserved.
//

import Foundation
import DSLogger
import MNUtils

// import Codextended

fileprivate let dlog : DSLogger? = DLog.forClass("AppSettings")?.setting(verbose: false)

// A singleton for all app settings, saves and loads from a json file the last saved settings.
// "Other" are all settings properties that are distributed around the app as properties of other classes. They are still connected and saved into this settings file, under the "other" dictionary.
final class AppSettings : AppSettingProvider, JSONFileSerializable {
    func blockChanges(block: (AppSettingProvider) -> Void) {
        
    }
    
    
    #if VAPOR
    static let FILENAME = AppConstants.BSERVER_APP_SETTINGS_FILENAME
    #else
    static let FILENAME = AppConstants.CLIENT_SETTINGS_FILENAME
    #endif
    
    static var _isLoaded : Bool = false
    static var _initingShared : Bool = false
    static var _defaultResponWithReqId = Dictionary<BuildType, Bool>(uniqueKeysWithValues:[(BuildType.all, true)])
    static var _defaultResponWithSelfUserId = Dictionary<BuildType, Bool>(uniqueKeysWithValues:[(BuildType.all, true)])
    static var _defaultParamKeysToNeverRedirect : [String] = ["password", "pwd", "email", "phoneNr", "phoneNumber" ,"phone", "token",
                                                         "accessToken", "user"]
    
    @SkipEncode private var _changes : [String] = []
    @SkipEncode private var _isLoading : Bool = false
    @SkipEncode private var _isBlockChanges : Bool = false
    
    struct AppSettingsGlobal : Codable {
        @AppSettable(name:"global.newUsernameAllowedTypes", default:UsernameType.allActive) var newUsernameAllowedTypes : [UsernameType]
        @AppSettable(name:"global.existingAllowedTypes", default:UsernameType.allActive) var existingAllowedTypes : [UsernameType]
    }
    
    struct AppSettingsClient : Codable {
        @AppSettable(name:"client.allowsAnalyze", default:true) var allowsAnalyze : Bool
        @AppSettable(name:"client.showsSplashScreenOnInit", default:true) var showsSplashScreenOnInit : Bool
        @AppSettable(name:"client.splashScreenCloseBtnWillCloseApp", default:true) var splashScreenCloseBtnWillCloseApp : Bool
        @AppSettable(name:"client.tooltipsShowKeyboardShortcut", default:true) var tooltipsShowKeyboardShortcut : Bool
    }
    
    struct AppSettingsServer : Codable {
        @AppSettable(name:"server.requestCount", default:0) var requestCount : UInt64
        @AppSettable(name:"server.requestSuccessCount", default:0) var requestSuccessCount : UInt64
        @AppSettable(name:"server.requestFailCount", default:0) var requestFailCount : UInt64
        @AppSettable(name:"server.respondWithRequestUUID", default:AppSettings._defaultResponWithReqId) var respondWithRequestUUID : Dictionary<BuildType, Bool>
        @AppSettable(name:"server.respondWithSelfUserUUID", default:AppSettings._defaultResponWithSelfUserId) var responWithSelfUserUUID : Dictionary<BuildType, Bool>
        
        // Params that the server should NEVER redirect from one endpoint / page to another:
        @AppSettable(name:"server.paramKeysToNeverRedirect", default:AppSettings._defaultParamKeysToNeverRedirect) var paramKeysToNeverRedirect : [String]
        
        var isShouldRespondWithRequestUUID : Bool {
            return respondWithRequestUUID[BuildType.currentBuildType] ?? true == true
        }
        var isShouldRespondWithSelfUserUUID : Bool {
            return responWithSelfUserUUID[BuildType.currentBuildType] ?? true == true
        }
    }
    
    struct AppSettingsStats : Codable {
        @AppSettable(name:"stats.launchCount", default:0) var launchCount : Int
        @AppSettable(name:"stats.firstLaunchDate", default:Date()) var firstLaunchDate : Date
        @AppSettable(name:"stats.lastLaunchDate", default:Date()) var lastLaunchDate : Date
    }
    
    struct AppSettingsDebug : Codable {
        // All default values should be production values.
        @AppSettable(name:"debug.isSimulateNoNetwork", default:false) var isSimulateNoNetwork : Bool
    }
    
    private enum CodingKeys: String, CodingKey {
        case global = "global"
        case server = "server"
        case client = "client"
        case stats = "stats"
        case debug = "debug"
        case other = "other"
        
        static var all : [CodingKeys] = [.global, .server, .client, .stats, .debug, .other]
        
        static func isOther(key:String)->Bool {
            let prx = key.lowercased().components(separatedBy: ".").first ?? key.lowercased()
            if let key = CodingKeys(stringValue: prx) {
                return (key == .other)
            } else {
                return true
            }
        }
    }
    
    var global : AppSettingsGlobal
    var client : AppSettingsClient?
    var server : AppSettingsServer?
    var stats : AppSettingsStats
    var debug : AppSettingsDebug?
    var other : [String:Any] = [:]
    
    var wasChanged : Bool {
        return _changes.count > 0
    }
    
    static var isLoaded : Bool {
        return Self._isLoaded
    }
    
    var isLoaded : Bool {
        return Self.isLoaded && !_isLoading
    }
    
    // MARK: Private
    
    internal static func noteChange(_ change:String, newValue:AnyCodable) {
        AppSettings.shared.noteChange(change, newValue:newValue)
    }
    
    static private func pathToSettingsFile()->URL? {
        guard var path = FileManager.default.urls(for: FileManager.SearchPathDirectory.applicationSupportDirectory,
                                                   in: FileManager.SearchPathDomainMask.userDomainMask).first else {
            return nil
        }
        
        // App Name:
        let appName = Bundle.main.bundleName?.capitalized.replacingOccurrences(of: .whitespaces, with: "_") ?? "Bundle.main.bundleName == nil !"
        path = path.appendingPathComponent(appName)
        
        // Create folder if needed
        if !FileManager.default.fileExists(atPath: path.absoluteString) {
            do {
                try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            } catch let error {
                dlog?.warning("pathToSettingsFile failed crating /\(appName)/ folder. error: " + error.localizedDescription)
                return nil
            }
        }
        
        path = path.appendingPathComponent(self.FILENAME).appendingPathExtension("json")
        return path
    }
    
    static private func registerIffyCodables() {
        
        // Client:
        #if !VAPOR
        StringAnyDictionary.registerClass(PreferencesVC.PreferencesPage.self)
        #endif
        
        // Server:
        #if VAPOR
//          StringAnyDictionary.registerClass(?? .... )
        #endif
        
        // All Builds:
        StringAnyDictionary.registerType([String:String].self) // see UnkeyedEncodingContainerEx
    }
    
    // MARK: Public
    func noteChange(_ change:String, newValue:Any) {
        dlog?.verbose("changed: \(change) = \(newValue)")
        _changes.append(change + " = \(newValue)")
        
        guard self.isLoaded else {
            return
        }
        
        // "Other" are all settings properties that are distributed around the app as properties of other classes. They are still connected and saved into this settings file, under the "other" dictionary.
        if CodingKeys.isOther(key: change) {
            other[change] = newValue
        }
        
        // debounce
        // TimedEventFilter.shared.filterEvent(key: "AppSettings.changes", threshold: 0.3, accumulating: change) { changes in
        TimedEventFilter.shared.filterEvent(key: "AppSettings.changes", threshold: 0.2) {
            if self._changes.count > 0 {
                 dlog?.verbose("changed: \(self._changes.descriptionsJoined)")
                
                // Want to save all changes to settings into a seperate log?
                // Do it here! - use self._changes
                
                self.saveIfNeeded()
            }
        }
    }
    
    func blockChanges(block:(_ settings : AppSettings)->Void) {
        self._isBlockChanges = true
        block(self)
        self._isBlockChanges = false
        self.saveIfNeeded()
    }
    
    func resetToDefaults() {
        self.global.existingAllowedTypes = UsernameType.allActive
        self.global.newUsernameAllowedTypes = UsernameType.allActive
        self.saveIfNeeded()
    }
    
    @discardableResult func saveIfNeeded()->Bool {
        if self.wasChanged && self.save() {
            self._changes.removeAll()
            return true
        }
        return false
    }
    
    @discardableResult
    func save()->Bool {
        if let path = Self.pathToSettingsFile() {
            let isDidSave = self.saveToJSON(path, prettyPrint: Debug.IS_DEBUG).isSuccess
            UserDefaults.standard.synchronize()
            dlog?.successOrFail(condition: isDidSave, "Saving settings")
            return isDidSave
        }
        return false
    }
    
    // MARK: Singleton
    private static var _shared : AppSettings? = nil
    public static var shared : AppSettings {
        var result : AppSettings? = nil
        
        if let shared = _shared {
            return shared
        } else if let path = pathToSettingsFile() {
            
            if !_initingShared {
                _initingShared = true
                
                Self.registerIffyCodables()
                
                //  Find setings file in app folder (icloud?)
                let res = Self.loadFromJSON(path)

                switch res {
                case .success(let instance):
                    result = instance
                    Self._isLoaded = true
                    Self._initingShared = false
                    dlog?.success("loaded from: \(path.absoluteString) other: \(instance.other.keysArray.descriptionsJoined)")
                case .failure(let error):
                    let appErr = AppError(error: error)
                    dlog?.fail("Failed loading file, will create new instance. error:\(appErr) path:\(path.absoluteString)")
                     // Create new instance
                     result = AppSettings()
                     _ = result?.saveToJSON(path, prettyPrint: Debug.IS_DEBUG)
                }
            } else {
                dlog?.warning(".shared Possible timed recursion! stack: " + Thread.callStackSymbols.descriptionLines)
            }
        }
        
        _shared = result
        return result!
    }
    
    private init() {
        _isLoading = false
        
        #if VAPOR
        server = AppSettingsServer()
        client = nil
        #else
        client = AppSettingsClient()
        server = nil
        #endif
        
        global = AppSettingsGlobal()
        stats = AppSettingsStats()
        debug = Debug.IS_DEBUG ? AppSettingsDebug() : nil
        
        // rest to defaults:
        if Debug.RESET_SETTINGS_ON_INIT {
            self.resetToDefaults()
        }
        
        dlog?.info("Init \(String(memoryAddressOf: self))")
    }
    
    deinit {
        dlog?.info("deinit \(String(memoryAddressOf: self))")
    }
    
    // MARK: Codable
    func encode(to encoder: Encoder) throws {
        var cont = encoder.container(keyedBy: CodingKeys.self)
        
        // Save depending on different condition:
        if SettingsEnv.currentEnv == .server {
            try cont.encode(server, forKey: CodingKeys.server)
        }
        if SettingsEnv.currentEnv == .client {
            try cont.encode(client, forKey: CodingKeys.client)
        }
        
        // Save for all builds
        try cont.encode(global, forKey: CodingKeys.global)
        try cont.encode(stats, forKey: CodingKeys.stats)
        
        if Debug.IS_DEBUG {
            try cont.encode(debug, forKey: CodingKeys.debug)
        }
        
        if other.count > 0 {
            var sub = cont.nestedUnkeyedContainer(forKey: .other)
            try sub.encode(dic: other, encoder:encoder)
        }
    }
    
    required init(from decoder: Decoder) throws {
        _isLoading = true
        dlog?.verbose("loading from decoder:")
        
        Self._isLoaded = false
        _changes = []
        debug = nil
        
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode depending on different conditions:
        if SettingsEnv.currentEnv == .server {
            server = try values.decodeIfPresent(AppSettingsServer.self, forKey: CodingKeys.server)
        } else {
            server = nil
        }
        
        if SettingsEnv.currentEnv == .client {
            client = try values.decodeIfPresent(AppSettingsClient.self, forKey: CodingKeys.client)
        } else {
            client = nil
        }
        
        // Decode always:
        global = try values.decode(AppSettingsGlobal.self, forKey: CodingKeys.global)
        stats = try values.decode(AppSettingsStats.self, forKey: CodingKeys.stats)
        if Debug.IS_DEBUG {
            debug = try values.decodeIfPresent(AppSettingsDebug.self, forKey: CodingKeys.debug) ?? AppSettingsDebug()
        }
        
        if values.allKeys.contains(.other) {
            var sub = try values.nestedUnkeyedContainer(forKey: .other)
            let strAny = try sub.decodeStringAnyDict(decoder: decoder) // parse the saved string/s into a k-v dictionary
            if Debug.IS_DEBUG && sub.count != strAny.count {
                dlog?.note("Failed decoding some StringLosslessConvertible. SUCCESSFUL keys: \(strAny.keysArray.descriptionsJoined). Find which key is missing.")
            }
            for (key, val) in strAny {
                if let val = val as? AnyCodable {
                    other[key] = val
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(delayFromNow: 0.05) {
            self._isLoading = false
            dlog?.success("loaded from decoder")
        }
    }
}
