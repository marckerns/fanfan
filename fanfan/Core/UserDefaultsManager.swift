//
//  File: UserDefaultsManager.swift / 文件：UserDefaultsManager.swift
//  Target: fanfan / 目标：fanfan
//
//  Created by haobin on 2026/5/15. / 创建者：haobin，日期：2026/5/15。
//  Description: Persistent user settings storage. / 描述：用户设置的持久化存储。
//

import Foundation

class UserDefaultsManager {
    static let shared = UserDefaultsManager()
    
    private let defaults = UserDefaults.standard
    
    private init() {}
    
    // MARK: - Fan Control Settings / 中文：风扇控制设置
    
    var controlMode: ControlMode {
        get {
            if let mode = defaults.string(forKey: "fanControlMode") {
                return ControlMode(rawValue: mode) ?? .manual
            }
            return .manual
        }
        set {
            defaults.set(newValue.rawValue, forKey: "fanControlMode")
        }
    }
    
    var manualFanSpeed: Int {
        get {
            let speed = defaults.integer(forKey: "manualFanSpeed")
            return speed > 0 ? speed : 2000
        }
        set {
            defaults.set(newValue, forKey: "manualFanSpeed")
        }
    }
    
    var autoThreshold: Double {
        get {
            let threshold = defaults.double(forKey: "autoThreshold")
            return threshold > 0 ? threshold : 60.0
        }
        set {
            defaults.set(newValue, forKey: "autoThreshold")
        }
    }
    
    var autoMaxSpeed: Int {
        get {
            let speed = defaults.integer(forKey: "autoMaxSpeed")
            return speed > 0 ? speed : 4000
        }
        set {
            defaults.set(newValue, forKey: "autoMaxSpeed")
        }
    }
    
    // MARK: - Launch at Login / 中文：Launch at Login 分区
    
    var launchAtLogin: Bool {
        get {
            return defaults.bool(forKey: "launchAtLogin")
        }
        set {
            defaults.set(newValue, forKey: "launchAtLogin")
        }
    }
    
    // MARK: - Temperature Units / 中文：Temperature Units 分区
    
    var useCelsius: Bool {
        get {
            return defaults.object(forKey: "useCelsius") as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: "useCelsius")
        }
    }
    
    // MARK: - Monitoring Settings / 中文：Monitoring Settings 分区
    
    var monitoringInterval: TimeInterval {
        get {
            let interval = defaults.double(forKey: "monitoringInterval")
            return interval > 0 ? interval : 2.0
        }
        set {
            defaults.set(newValue, forKey: "monitoringInterval")
        }
    }
    
    // MARK: - UI Settings / 中文：UI Settings 分区
    
    var statusBarDisplayMode: String {
        get {
            return defaults.string(forKey: "statusBarDisplayMode") ?? "temperature"
        }
        set {
            defaults.set(newValue, forKey: "statusBarDisplayMode")
        }
    }
    
    var enableNotifications: Bool {
        get {
            return defaults.object(forKey: "enableNotifications") as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: "enableNotifications")
        }
    }
    
    var highTempAlert: Double {
        get {
            let temp = defaults.double(forKey: "highTempAlert")
            return temp > 0 ? temp : 85.0
        }
        set {
            defaults.set(newValue, forKey: "highTempAlert")
        }
    }
    
    var autoSwitchMode: Bool {
        get {
            return defaults.object(forKey: "autoSwitchMode") as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: "autoSwitchMode")
        }
    }
    
    // MARK: - Helper Methods / 中文：Helper Methods 分区
    
    func resetToDefaults() {
        defaults.removeObject(forKey: "fanControlMode")
        defaults.removeObject(forKey: "manualFanSpeed")
        defaults.removeObject(forKey: "autoThreshold")
        defaults.removeObject(forKey: "autoMaxSpeed")
        defaults.removeObject(forKey: "launchAtLogin")
        defaults.removeObject(forKey: "useCelsius")
        defaults.removeObject(forKey: "monitoringInterval")
        defaults.removeObject(forKey: "statusBarDisplayMode")
        defaults.removeObject(forKey: "enableNotifications")
        defaults.removeObject(forKey: "highTempAlert")
        defaults.removeObject(forKey: "autoSwitchMode")
    }
}
