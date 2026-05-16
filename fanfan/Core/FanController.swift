//
//  File: FanController.swift / 文件：FanController.swift
//  Target: fanfan / 目标：fanfan
//
//  Created by haobin on 2026/5/15. / 创建者：haobin，日期：2026/5/15。
//  Description: SMC fan control with per-fan targets and hardware-derived RPM limits. / 描述：支持单风扇目标值和硬件 RPM 边界的 SMC 风扇控制。
//

import Foundation
import Combine
import IOKit

enum ControlMode: String, CaseIterable {
    case manual
    case automatic
    case system
}

class FanController: ObservableObject {
    @Published var mode: ControlMode = .automatic
    /// Unified manual target (single slider / legacy settings). / 中文：Unified 手动 目标 (single 滑杆 / legacy 设置).
    @Published var manualSpeed: Int = 2000
    /// When `perFanManualControl` is true, each index maps to `F%dTg` for fan `d`. / 中文：When `per风扇手动控制` is true, each index maps to `F%dTg` for 风扇 `d`.
    @Published var manualSpeeds: [Int] = []
    @Published var perFanManualControl: Bool = false

    @Published var autoThreshold: Double = 55.0
    @Published var autoMaxSpeed: Int = 3600
    @Published var autoAggressiveness: Double = 1.5  // 0.0 = always min, 1.5 = temp-based, 3.0 = always max

    // PID gain overrides — nil means use the formula derived from aggressiveness. / 中文：PID 增益覆盖值；nil 表示使用由响应强度推导出的公式。
    // Exposed in the advanced/debug settings pane. / 中文：Exposed in the advanced/debug 设置 pane.
    @Published var pidKpCustom: Double? = nil
    @Published var pidKiCustom: Double? = nil
    @Published var pidKdCustom: Double? = nil

    @Published var isControlEnabled = false
    @Published var lastWriteSuccess = false
    @Published var statusMessage: String = ""
    /// Largest target RPM last applied (used for auto-mode hysteresis). / 中文：Largest 目标 RPM last applied (used for auto-模式 滞回).
    @Published var lastAppliedSpeed: Int = 0

    private weak var systemMonitor: SystemMonitor?
    private var autoControlTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Smart Scheduling State / 中文：Smart Scheduling State 分区

    /// Temperature history for trend prediction (last N samples) / 中文：温度 历史记录 for trend prediction (last N 采样s)
    private var tempHistory: [Double] = []
    private let tempHistoryMaxCount: Int = 10
    private var lastTempSampleTime: Date = Date()

    /// Hysteresis and noise optimization / 中文：滞回 and noise optimization
    private let hysteresisRPM: Int = 200
    private var lastSpeedChangeTime: Date = Date()
    private let minimumHoldSeconds: TimeInterval = 3.0
    private var rampTargetSpeed: Int = 0
    private var rampCurrentSpeed: Int = 0

    // MARK: - PID State / 中文：PID 状态

    private var pidIntegral: Double = 0
    private var pidLastError: Double = 0
    private var pidLastUpdateTime: Date = Date()
    /// Anti-windup clamp on the integral term, in RPM-seconds-equivalent units. / 中文：Anti-windup 夹取 on the integral term, in RPM-seconds-equivalent units.
    /// Tuned so Ki * pidIntegralMaxAbs ≈ full RPM range at typical gains. / 中文：Tuned so Ki * pidIntegralMaxAbs ≈ full RPM range at typical gains.
    private let pidIntegralMaxAbs: Double = 600

    /// Default proportional gain: each °C of error contributes / 中文：默认比例增益：每 1°C 误差都会贡献转速修正。
    /// (range × aggressiveness / 10) RPM. At aggressiveness=1.5, range=3200 / 中文：(range × aggressiveness / 10) RPM. At aggressiveness=1.5, range=3200
    /// → Kp ≈ 480 RPM/°C → 5°C overshoot drives +2400 RPM immediately. / 中文：→ Kp ≈ 480 RPM/°C → 5°C overshoot drives +2400 RPM immediately.
    private var pidKp: Double {
        if let custom = pidKpCustom { return custom }
        let range = Double(unifiedMaxClamp - unifiedMinClamp)
        return range * autoAggressiveness / 10.0
    }

    /// Integral time constant ~60 s: long enough to absorb sensor noise, / 中文：Integral time constant ~60 s: long enough to absorb 传感器 noise,
    /// short enough that the loop converges to the target within ~2 min. / 中文：short enough that the loop converges to the 目标 within ~2 min.
    private var pidKi: Double {
        if let custom = pidKiCustom { return custom }
        return pidKp / 60.0
    }

    /// Derivative time constant ~3 s: predicts where temperature is heading / 中文：Derivative time constant ~3 s: predicts where 温度 is heading
    /// over the next few cycles, lets fans pre-empt sustained ramps. / 中文：over the next few cycles, lets 风扇s pre-empt sustained ramps.
    private var pidKd: Double {
        if let custom = pidKdCustom { return custom }
        return pidKp * 3.0
    }

    private func resetPIDState() {
        pidIntegral = 0
        pidLastError = 0
        pidLastUpdateTime = Date()
    }

    /// Response curve presets / 中文：响应曲线预设。
    enum ResponsePreset: String, CaseIterable {
        case silent, balanced, performance, custom

        var aggressiveness: Double {
            switch self {
            case .silent: return 0.5
            case .balanced: return 1.5
            case .performance: return 2.5
            case .custom: return -1 // uses stored value
            }
        }
    }

    init(systemMonitor: SystemMonitor) {
        self.systemMonitor = systemMonitor
        loadSettings()

        systemMonitor.$fanMaxSpeeds
            .combineLatest(systemMonitor.$fanMinSpeeds, systemMonitor.$numberOfFans)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, fanCount in
                guard let self = self, fanCount > 0 else { return }
                self.onHardwareLimitsUpdated()
            }
            .store(in: &cancellables)

        systemMonitor.$numberOfFans
            .receive(on: DispatchQueue.main)
            .filter { $0 > 0 }
            .first()
            .sink { [weak self] _ in
                print("FanController: Fans detected, applying initial settings")
                self?.applyInitialSettings()
            }
            .store(in: &cancellables)
    }

    deinit {
        stopAutoControl()
        restoreAutomaticControl()
    }

    // MARK: - Hardware-derived clamps / 中文：Hardware-derived clamps 分区

    private var unifiedMinClamp: Int {
        systemMonitor?.fanMinSpeeds.min() ?? FanRPMBounds.fallbackMinWhenSMCUnreadable
    }

    private var unifiedMaxClamp: Int {
        systemMonitor?.fanMaxSpeeds.max() ?? FanRPMBounds.fallbackMaxWhenSMCUnreadable
    }

    private func minRPM(for index: Int) -> Int {
        guard let monitor = systemMonitor,
              index >= 0,
              index < monitor.fanMinSpeeds.count else {
            return FanRPMBounds.fallbackMinWhenSMCUnreadable
        }
        return monitor.fanMinSpeeds[index]
    }

    private func maxRPM(for index: Int) -> Int {
        guard let monitor = systemMonitor,
              index >= 0,
              index < monitor.fanMaxSpeeds.count else {
            return FanRPMBounds.fallbackMaxWhenSMCUnreadable
        }
        return monitor.fanMaxSpeeds[index]
    }

    private func clampToFan(_ speed: Int, index: Int) -> Int {
        max(minRPM(for: index), min(maxRPM(for: index), speed))
    }

    private func clampUnified(_ speed: Int) -> Int {
        max(unifiedMinClamp, min(unifiedMaxClamp, speed))
    }

    private func onHardwareLimitsUpdated() {
        guard let monitor = systemMonitor, monitor.numberOfFans > 0 else { return }
        ensureManualSpeedsSize()
        manualSpeed = clampUnified(manualSpeed)
        autoMaxSpeed = clampUnified(autoMaxSpeed)
        if !manualSpeeds.isEmpty {
            manualSpeeds = manualSpeeds.enumerated().map { clampToFan($0.element, index: $0.offset) }
        }
        saveSettings()

        if mode == .manual && isControlEnabled {
            applyManualTargets()
        } else if mode == .automatic && isControlEnabled {
            lastAppliedSpeed = 0
            updateAutoControl()
        }
    }

    private func ensureManualSpeedsSize() {
        guard let monitor = systemMonitor, monitor.numberOfFans > 0 else { return }
        let n = monitor.numberOfFans
        if manualSpeeds.count < n {
            var copy = manualSpeeds
            let template = copy.last ?? manualSpeed
            while copy.count < n {
                let idx = copy.count
                copy.append(clampToFan(template, index: idx))
            }
            manualSpeeds = copy
        } else if manualSpeeds.count > n {
            manualSpeeds = Array(manualSpeeds.prefix(n))
        }
    }

    private func syncManualSpeedsFromUnified() {
        guard let monitor = systemMonitor, monitor.numberOfFans > 0 else { return }
        manualSpeeds = (0..<monitor.numberOfFans).map { clampToFan(manualSpeed, index: $0) }
    }

    // MARK: - Lifecycle / 中文：生命周期

    private func applyInitialSettings() {
        print("FanController: Applying initial settings - mode: \(mode)")
        switch mode {
        case .manual:
            enableManualMode()
            ensureManualSpeedsSize()
            if !perFanManualControl {
                syncManualSpeedsFromUnified()
            }
            applyManualTargets()
        case .automatic:
            startAutoControl()
        case .system:
            stopAutoControl()
            restoreAutomaticControl()
        }
    }

    func reapplySettings() {
        print("FanController: Reapplying settings after wake - mode: \(mode)")
        guard let monitor = systemMonitor, monitor.numberOfFans > 0 else {
            print("FanController: No fans detected yet, retrying in 2 seconds...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.reapplySettings()
            }
            return
        }

        switch mode {
        case .manual:
            enableManualMode()
            ensureManualSpeedsSize()
            if !perFanManualControl {
                syncManualSpeedsFromUnified()
            }
            applyManualTargets()
            print("FanController: Manual mode reapplied")
        case .automatic:
            enableManualMode()
            startAutoControl()
            lastAppliedSpeed = 0
            updateAutoControl()
            print("FanController: Auto mode reapplied")
        case .system:
            stopAutoControl()
            restoreAutomaticControl()
            print("FanController: System mode reapplied")
        }
    }

    /// Toggle independent sliders for each fan (manual mode only). / 中文：Toggle independent 滑杆s for each 风扇 (手动 模式 only).
    func setPerFanManualControl(_ enabled: Bool) {
        perFanManualControl = enabled
        if enabled {
            syncManualSpeedsFromUnified()
        } else {
            if !manualSpeeds.isEmpty {
                let avg = Int(round(Double(manualSpeeds.reduce(0, +)) / Double(manualSpeeds.count)))
                manualSpeed = clampUnified(avg)
            }
            syncManualSpeedsFromUnified()
        }
        saveSettings()
        if mode == .manual && isControlEnabled {
            applyManualTargets()
        }
    }

    func setManualSpeed(_ speed: Int) {
        guard mode == .manual else { return }
        manualSpeed = clampUnified(speed)
        if !perFanManualControl {
            syncManualSpeedsFromUnified()
        }
        if isControlEnabled {
            applyManualTargets()
        }
        saveSettings()
    }

    func setManualSpeed(fanIndex: Int, speed: Int) {
        guard mode == .manual, perFanManualControl else { return }
        ensureManualSpeedsSize()
        guard fanIndex >= 0, fanIndex < manualSpeeds.count else { return }
        var next = manualSpeeds
        next[fanIndex] = clampToFan(speed, index: fanIndex)
        manualSpeeds = next
        saveSettings()
        if isControlEnabled {
            applyManualTargets()
        }
    }

    func setMode(_ newMode: ControlMode) {
        mode = newMode

        if newMode == .automatic {
            restoreAutomaticControl()
            startAutoControl()
        } else if newMode == .manual {
            stopAutoControl()
            enableManualMode()
            ensureManualSpeedsSize()
            if !perFanManualControl {
                syncManualSpeedsFromUnified()
            }
            applyManualTargets()
        } else {
            stopAutoControl()
            restoreAutomaticControl()
        }

        saveSettings()
    }

    private func enableManualMode() {
        guard systemMonitor != nil else {
            statusMessage = "No system monitor available"
            return
        }
        isControlEnabled = true
        statusMessage = "Manual control enabled"
        print("Fan Control: Manual control enabled")
    }

    func restoreAutomaticControl() {
        guard let monitor = systemMonitor else { return }
        guard monitor.numberOfFans > 0 else { return }

        var allSuccess = true
        for i in 0..<monitor.numberOfFans {
            if !runSmcHelper(args: ["auto", "\(i)"]) {
                allSuccess = false
            }
        }

        if allSuccess {
            isControlEnabled = false
            statusMessage = "Automatic mode restored"
            print("Fan Control: Automatic mode restored")
        } else {
            statusMessage = "Failed to restore auto mode"
            print("Fan Control: Failed to restore auto mode")
        }
    }

    private func applyManualTargets() {
        guard let monitor = systemMonitor else {
            statusMessage = "No system monitor"
            lastWriteSuccess = false
            return
        }
        guard monitor.numberOfFans > 0 else {
            statusMessage = "No fans detected"
            lastWriteSuccess = false
            return
        }

        ensureManualSpeedsSize()
        var targets: [Int] = []
        for i in 0..<monitor.numberOfFans {
            let raw: Int
            if perFanManualControl, i < manualSpeeds.count {
                raw = manualSpeeds[i]
            } else {
                raw = manualSpeed
            }
            targets.append(clampToFan(raw, index: i))
        }
        applyFanTargets(targets)
    }

    private func applyFanTargets(_ targets: [Int]) {
        guard let monitor = systemMonitor else {
            statusMessage = "No system monitor"
            lastWriteSuccess = false
            return
        }
        guard monitor.numberOfFans > 0, targets.count == monitor.numberOfFans else {
            statusMessage = "Fan target mismatch"
            lastWriteSuccess = false
            return
        }

        var allSuccess = true
        for (i, t) in targets.enumerated() {
            let safe = max(FanRPMBounds.absoluteWriteMinRPM, min(FanRPMBounds.absoluteWriteMaxRPM, t))
            if !runSmcHelper(args: ["set", "\(i)", "\(safe)"]) {
                allSuccess = false
            }
        }

        if allSuccess {
            let parts = targets.enumerated().map { "F\($0.offset): \($0.element)" }.joined(separator: ", ")
            statusMessage = "Fan targets RPM — \(parts)"
            lastWriteSuccess = true
            print("Fan Control: \(parts)")
        } else {
            statusMessage = "Failed to set fan speed"
            lastWriteSuccess = false
        }
    }

    private func runSmcHelper(args: [String]) -> Bool {
        guard let command = args.first else { return false }

        switch command {
        case "set":
            guard args.count == 3,
                  let fanIndex = Int(args[1]),
                  let rpm = Int(args[2]) else {
                return false
            }
            return SMCDaemonClient.setFanSpeed(fanIndex: fanIndex, rpm: rpm)
        case "auto":
            guard args.count == 2,
                  let fanIndex = Int(args[1]) else {
                return false
            }
            return SMCDaemonClient.setFanAuto(fanIndex: fanIndex)
        default:
            return false
        }
    }

    func startAutoControl() {
        stopAutoControl()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Seed ramp from the fan's current real RPM so the first cycles / 中文：Seed ramp from the 风扇's current real RPM so the first cycles
            // don't waste seconds climbing from 0 through the hardware floor. / 中文：避免前几个周期从 0 慢慢爬升到硬件下限而浪费时间。
            if let currentMax = self.systemMonitor?.fanSpeeds.max(), currentMax > 0 {
                self.lastAppliedSpeed = currentMax
            }
            self.resetPIDState()
            self.updateAutoControl()
            self.autoControlTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.updateAutoControl()
            }
            RunLoop.current.add(self.autoControlTimer!, forMode: .common)
        }
    }

    func stopAutoControl() {
        autoControlTimer?.invalidate()
        autoControlTimer = nil
    }

    private func updateAutoControl() {
        guard mode == .automatic, let monitor = systemMonitor else { return }

        let currentTemp = max(
            monitor.cpuTemperature ?? 0,
            monitor.gpuTemperature ?? 0
        )

        guard currentTemp > 0, monitor.numberOfFans > 0 else { return }

        // Update temperature history (used by the status-message trend label) / 中文：Update 温度 历史记录 (used by the 状态-message trend label)
        updateTempHistory(currentTemp)

        let autoCeiling = min(autoMaxSpeed, unifiedMaxClamp)
        let autoFloor = unifiedMinClamp

        // 1. PID feedback: drives temperature toward autoThreshold (target temp) / 中文：1. PID feedback: drives 温度 toward auto阈值 (目标 temp)
        let baseSpeed = pidResponse(temp: currentTemp, floor: autoFloor, ceiling: autoCeiling)

        // 2. Load-aware feedforward: pre-empts heat from sustained power draw / 中文：2. 负载-aware feedforward: pre-empts heat from sustained 功率 draw
        let loadAdjustment = loadAwareAdjustment(floor: autoFloor, ceiling: autoCeiling)

        // 3. Combine and clamp into the auto window / 中文：3. Combine and 夹取 into the auto 窗口
        let rawTarget = min(Double(autoCeiling), baseSpeed + loadAdjustment)
        let unifiedTarget = Int(max(Double(autoFloor), rawTarget))

        if !isControlEnabled {
            // Re-engage after firmware was running the fan (e.g., post screen-sleep / 中文：固件接管过风扇后（如屏幕息屏唤醒）重新接管时，
            // restoreAutomaticControl). Re-seed from the real RPM so the hysteresis / 中文：用真实转速重新 seed，让滞回基于风扇当前状态，
            // check tracks the fan's current state, not a stale Swift target that / 中文：而不是接管前那个可能恰好等于新 PID 目标的过期值——
            // could equal the new PID output and block the re-engagement write. / 中文：否则下次写入会被滞回挡住。
            lastAppliedSpeed = monitor.fanSpeeds.max() ?? 0
            enableManualMode()
        }

        // Build per-fan targets / 中文：Build per-风扇 目标s
        var targets: [Int] = []
        for i in 0..<monitor.numberOfFans {
            let mx = maxRPM(for: i)
            let mn = minRPM(for: i)
            let cap = min(mx, autoCeiling)
            targets.append(max(mn, min(unifiedTarget, cap)))
        }

        let representative = targets.max() ?? unifiedTarget

        // 5. Apply with hysteresis and minimum hold time / 中文：5. Apply with 滞回 and minimum hold time
        if shouldApplySpeed(representative) {
            // Ramp transition to avoid sudden noise changes / 中文：使用渐进过渡，避免噪声突然变化。
            let ramped = rampTransition(from: lastAppliedSpeed, to: representative)
            var rampedTargets: [Int] = []
            for i in 0..<monitor.numberOfFans {
                let mx = maxRPM(for: i)
                let mn = minRPM(for: i)
                rampedTargets.append(max(mn, min(ramped, mx)))
            }

            applyFanTargets(rampedTargets)
            lastAppliedSpeed = ramped
            lastSpeedChangeTime = Date()
            rampTargetSpeed = representative

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let parts = rampedTargets.enumerated().map { "F\($0.offset): \($0.element)" }.joined(separator: ", ")
                let trendStr = self.tempTrendDescription()
                self.statusMessage = "Auto — \(parts) \(trendStr)"
            }
        }
    }

    // MARK: - PID Response / 中文：PID 响应

    /// Closed-loop response toward `autoThreshold` (interpreted as target temp). / 中文：Closed-loop response toward `auto阈值` (interpreted as 目标 temp).
    /// Returns an absolute RPM in [floor, ceiling]; downstream clamps still apply. / 中文：Returns an absolute RPM in [floor, ceiling]; downstream 夹取s still apply.
    private func pidResponse(temp: Double, floor: Int, ceiling: Int) -> Double {
        let now = Date()
        let rawDt = now.timeIntervalSince(pidLastUpdateTime)
        let dt = max(0.1, min(5.0, rawDt))  // guard first call / suspended app

        let error = temp - autoThreshold
        let derivative = (error - pidLastError) / dt
        pidIntegral += error * dt
        pidIntegral = max(-pidIntegralMaxAbs, min(pidIntegralMaxAbs, pidIntegral))
        pidLastError = error
        pidLastUpdateTime = now

        let p = pidKp * error
        let i = pidKi * pidIntegral
        let d = pidKd * derivative

        // Center the output around the floor: when temp == target and the / 中文：Center the output around the floor: when temp == 目标 and the
        // integral has settled, the loop sits at the hardware minimum. The / 中文：积分项稳定后，控制环会停在硬件最低转速；
        // integral pulls the baseline up over time if that's not enough. / 中文：如果最低转速不足，积分项会随时间把基线拉高。
        let raw = Double(floor) + p + i + d
        return max(Double(floor), min(Double(ceiling), raw))
    }

    // MARK: - Temperature Trend Prediction / 中文：温度趋势预测

    private func updateTempHistory(_ temp: Double) {
        let now = Date()
        // Only sample at consistent intervals / 中文：Only 采样 at consistent intervals
        if now.timeIntervalSince(lastTempSampleTime) >= 1.5 {
            tempHistory.append(temp)
            if tempHistory.count > tempHistoryMaxCount {
                tempHistory.removeFirst()
            }
            lastTempSampleTime = now
        }
    }

    private func tempTrendDescription() -> String {
        guard tempHistory.count >= 3 else { return "(stabilizing)" }
        let recent = tempHistory.suffix(3)
        let slope = (recent.last! - recent.first!) / 2.0
        if slope > 1.0 { return "(rising fast)" }
        if slope > 0.2 { return "(rising)" }
        if slope < -1.0 { return "(cooling fast)" }
        if slope < -0.2 { return "(cooling)" }
        return "(stable)"
    }

    // MARK: - Load-Aware Scheduling / 中文：负载感知调度

    /// Adjust fan speed based on power consumption (if available) / 中文：Adjust 风扇 speed based on 功率 consumption (if available)
    private func loadAwareAdjustment(floor: Int, ceiling: Int) -> Double {
        guard let power = BatteryMonitor.shared.batteryInfo.powerWatts, power > 0.1 else {
            return 0
        }
        let range = Double(ceiling - floor)

        // High power + low temp = burst load, preemptively raise fans / 中文：High 功率 + low temp = burst 负载, preemptively raise 风扇s
        let currentTemp = tempHistory.last ?? 0
        if power > 25 && currentTemp < autoThreshold {
            // Burst detected: boost by up to 15% / 中文：检测到突发负载时，最多提升 15%。
            let burstFactor = min(0.15, (power - 25) / 100.0)
            return range * burstFactor
        }

        // Charging adds heat, slightly boost / 中文：充电会增加热量，因此略微提高转速。
        if BatteryMonitor.shared.batteryInfo.isCharging {
            return range * 0.05  // 5% boost while charging
        }

        return 0
    }

    // MARK: - Hysteresis & Noise Optimization / 中文：滞回与噪声优化

    private func shouldApplySpeed(_ target: Int) -> Bool {
        // First application / 中文：首次应用目标值。
        if lastAppliedSpeed == 0 { return true }

        // Minimum hold time check / 中文：检查最小保持时间。
        let elapsed = Date().timeIntervalSince(lastSpeedChangeTime)
        if elapsed < minimumHoldSeconds {
            // Only override hold time for significant changes (safety) / 中文：仅在变化显著时才出于安全原因覆盖保持时间。
            return abs(target - lastAppliedSpeed) >= 500
        }

        // Hysteresis: only change if difference exceeds threshold / 中文：滞回: only change if difference exceeds 阈值
        return abs(target - lastAppliedSpeed) >= hysteresisRPM
    }

    /// Gradual ramp to avoid sudden RPM jumps / 中文：Gradual ramp to avoid sudden RPM jumps
    private func rampTransition(from current: Int, to target: Int) -> Int {
        let maxStep = 1000  // Max RPM change per cycle
        let diff = target - current
        if abs(diff) <= maxStep { return target }
        return current + (diff > 0 ? maxStep : -maxStep)
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard

        if let savedMode = defaults.string(forKey: "fanControlMode") {
            mode = ControlMode(rawValue: savedMode) ?? .automatic
        }

        perFanManualControl = defaults.bool(forKey: "perFanManualControl")

        let savedManualSpeed = defaults.integer(forKey: "manualFanSpeed")
        if savedManualSpeed >= FanRPMBounds.absoluteWriteMinRPM && savedManualSpeed <= FanRPMBounds.absoluteWriteMaxRPM {
            manualSpeed = savedManualSpeed
        }

        if let savedPerFan = defaults.array(forKey: "manualFanSpeedsPerFan") as? [Int], !savedPerFan.isEmpty {
            manualSpeeds = savedPerFan
        }

        let savedThreshold = defaults.double(forKey: "autoThreshold")
        if savedThreshold >= 40 && savedThreshold <= 90 {
            autoThreshold = savedThreshold
        }

        let savedMaxSpeed = defaults.integer(forKey: "autoMaxSpeed")
        if savedMaxSpeed >= FanRPMBounds.absoluteWriteMinRPM && savedMaxSpeed <= FanRPMBounds.absoluteWriteMaxRPM {
            autoMaxSpeed = savedMaxSpeed
        }

        if defaults.object(forKey: "autoAggressiveness") != nil {
            let savedAggressiveness = defaults.double(forKey: "autoAggressiveness")
            if savedAggressiveness >= 0.0 && savedAggressiveness <= 3.0 {
                autoAggressiveness = savedAggressiveness
            }
        }

        pidKpCustom = defaults.object(forKey: "pidKpCustom") as? Double
        pidKiCustom = defaults.object(forKey: "pidKiCustom") as? Double
        pidKdCustom = defaults.object(forKey: "pidKdCustom") as? Double
    }

    func resetToSystemControl() {
        print("Fan Control: Resetting to system default...")
        stopAutoControl()
        restoreAutomaticControl()
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(mode.rawValue, forKey: "fanControlMode")
        defaults.set(perFanManualControl, forKey: "perFanManualControl")
        defaults.set(manualSpeed, forKey: "manualFanSpeed")
        defaults.set(manualSpeeds, forKey: "manualFanSpeedsPerFan")
        defaults.set(autoThreshold, forKey: "autoThreshold")
        defaults.set(autoMaxSpeed, forKey: "autoMaxSpeed")
        defaults.set(autoAggressiveness, forKey: "autoAggressiveness")

        if let v = pidKpCustom { defaults.set(v, forKey: "pidKpCustom") } else { defaults.removeObject(forKey: "pidKpCustom") }
        if let v = pidKiCustom { defaults.set(v, forKey: "pidKiCustom") } else { defaults.removeObject(forKey: "pidKiCustom") }
        if let v = pidKdCustom { defaults.set(v, forKey: "pidKdCustom") } else { defaults.removeObject(forKey: "pidKdCustom") }
    }

    func setAutoThreshold(_ threshold: Double) {
        autoThreshold = max(40, min(90, threshold))
        saveSettings()
        if mode == .automatic {
            resetPIDState()
            updateAutoControl()
        }
    }

    func setAutoMaxSpeed(_ speed: Int) {
        autoMaxSpeed = clampUnified(speed)
        saveSettings()
        if mode == .automatic {
            resetPIDState()
            updateAutoControl()
        }
    }

    func setAutoAggressiveness(_ value: Double) {
        autoAggressiveness = max(0.0, min(3.0, value))
        saveSettings()
        if mode == .automatic {
            resetPIDState()
            updateAutoControl()
        }
    }

    func setPIDGains(kp: Double?, ki: Double?, kd: Double?) {
        pidKpCustom = kp
        pidKiCustom = ki
        pidKdCustom = kd
        saveSettings()
        if mode == .automatic {
            resetPIDState()
            updateAutoControl()
        }
    }
}
