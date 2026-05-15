//
//  File: FanRPMBounds.swift / 文件：FanRPMBounds.swift
//  Target: fanfan / 目标：fanfan
//
//  Created by haobin on 2026/5/15. / 创建者：haobin，日期：2026/5/15。
//  Description: Central RPM limits for SMC reads, UI sliders, and writes. / 描述：SMC 读取、界面滑杆和写入操作共用的 RPM 限制。
//

import Foundation

/// Hardware fan RPM bounds used when SMC keys are missing or before telemetry arrives. / 中文：Hardware 风扇 RPM bounds used when SMC 键s are missing or before telemetry arrives.
enum FanRPMBounds {
    /// Typical Intel MacBook Pro ceiling; used only as an absolute write clamp. / 中文：Typical Intel MacBook Pro ceiling; used only as an absolute 写入 夹取.
    static let absoluteWriteMaxRPM = 8000

    static let absoluteWriteMinRPM = 500

    /// When `F%dMn` cannot be read, assume a quiet floor consistent with prior app behavior. / 中文：When `F%dMn` cannot be 读取, assume a quiet floor consistent with prior app behavior.
    static let fallbackMinWhenSMCUnreadable = 1000

    /// When `F%dMx` cannot be read, avoid assuming Intel-class 6500 RPM (incorrect on Apple Silicon). / 中文：When `F%dMx` cannot be 读取, avoid assuming Intel-class 6500 RPM (incorrect on Apple Sil图标).
    static let fallbackMaxWhenSMCUnreadable = 5200
}
