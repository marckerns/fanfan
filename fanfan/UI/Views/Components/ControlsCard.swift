//
//  File: ControlsCard.swift / 文件：ControlsCard.swift
//  Target: fanfan / 目标：fanfan
//
//  Created by haobin on 2026/5/15. / 创建者：haobin，日期：2026/5/15。
//  Description: Fan mode and slider controls in one dense card. / 描述：集中展示风扇模式与滑杆控制的紧凑卡片。
//

import SwiftUI

struct ControlsCard: View {
    @ObservedObject var viewModel: FanControlViewModel

    @Environment(\.colorScheme) private var scheme

    @State private var manualDraft: Double?
    @State private var manualApplyTask: Task<Void, Never>?
    @State private var perFanDraft: [Int: Double] = [:]
    @State private var perFanApplyTasks: [Int: Task<Void, Never>] = [:]
    @State private var selectedMode: ControlMode = .manual

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if selectedMode == .automatic {
                autoSliders
            } else if selectedMode == .manual {
                manualSliders
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .themedCard(scheme)
        .onAppear {
            selectedMode = viewModel.controlMode
        }
        .onChange(of: viewModel.controlMode) { _, newMode in
            selectedMode = newMode
        }
    }

    // MARK: - Header / 中文：头部

    private var header: some View {
        HStack(spacing: 6) {
            Text(String(format: NSLocalizedString("controls.header", comment: ""),
                        modeLabel(selectedMode).uppercased()))
                .font(Theme.label(10.5, weight: .semibold))
                .tracking(0.4)
                .foregroundColor(Theme.text3(scheme))

            Spacer()

            Picker("", selection: Binding(
                get: { selectedMode },
                set: { newMode in
                    guard newMode != selectedMode else { return }
                    selectedMode = newMode
                    DispatchQueue.main.async {
                        viewModel.setControlMode(newMode)
                    }
                }
            )) {
                Text(NSLocalizedString("popover.mode.manual", comment: "")).tag(ControlMode.manual)
                Text(NSLocalizedString("popover.mode.auto",   comment: "")).tag(ControlMode.automatic)
                Text(NSLocalizedString("popover.mode.system", comment: "")).tag(ControlMode.system)
            }
            .pickerStyle(.segmented)
            .frame(width: 168)
            .labelsHidden()
        }
    }

    // MARK: - Auto / 中文：自动

    private var autoSliders: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledSlider(
                label: NSLocalizedString("popover.threshold", comment: ""),
                value: Binding(
                    get: { viewModel.autoThreshold },
                    set: { viewModel.setAutoThreshold($0) }
                ),
                range: 40...90, step: 1,
                format: { String(format: "%.0f°C", $0) },
                accent: .thermal
            )
            LabeledSlider(
                label: NSLocalizedString("popover.max_speed", comment: ""),
                value: Binding(
                    get: { Double(viewModel.autoMaxSpeed) },
                    set: { viewModel.setAutoMaxSpeed(Int($0)) }
                ),
                range: rpmRange,
                step: 50,
                format: { "\(Int($0.rounded())) rpm" }
            )
            LabeledSlider(
                label: NSLocalizedString("popover.response", comment: ""),
                value: Binding(
                    get: { Double(responseIndex(for: viewModel.autoAggressiveness)) },
                    set: { viewModel.setAutoAggressiveness(responseStep($0)) }
                ),
                range: 0...Double(responseSteps.count - 1), step: 1,
                format: { responseLabel(for: responseStep($0)) }
            )
        }
    }

    // MARK: - Manual / 中文：手动

    private var manualSliders: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.numberOfFans > 1 {
                Toggle(isOn: Binding(
                    get: { viewModel.perFanManualControl },
                    set: { viewModel.setPerFanManualControl($0) }
                )) {
                    Text(NSLocalizedString("fan.separate_targets", comment: ""))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Theme.text1(scheme))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if viewModel.perFanManualControl && viewModel.numberOfFans > 1 {
                ForEach(0..<viewModel.numberOfFans, id: \.self) { i in
                    perFanRow(index: i)
                }
            } else {
                LabeledSlider(
                    label: NSLocalizedString("fan.speed", comment: ""),
                    value: Binding(
                        get: { manualDraft ?? Double(viewModel.manualSpeed) },
                        set: { newValue in
                            manualDraft = newValue
                            scheduleApply(Int(newValue))
                        }
                    ),
                    range: rpmRange,
                    step: 50,
                    format: { "\(Int($0.rounded())) rpm" }
                )
                .onChange(of: viewModel.manualSpeed) { _, new in
                    if let d = manualDraft, Int(d) == new { manualDraft = nil }
                }
            }
        }
    }

    private func perFanRow(index: Int) -> some View {
        let mn = Double(viewModel.minRPM(atFan: index))
        let mx = Double(Swift.max(viewModel.maxRPM(atFan: index), viewModel.minRPM(atFan: index) + 1))
        let current: Double = {
            if let d = perFanDraft[index] { return d }
            if index < viewModel.manualSpeeds.count {
                return Double(viewModel.manualSpeeds[index])
            }
            return Double(viewModel.manualSpeed)
        }()
        return LabeledSlider(
            label: String(format: NSLocalizedString("fan.number", comment: ""), index + 1),
            value: Binding(
                get: { current },
                set: { v in
                    perFanDraft[index] = v
                    schedulePerFanApply(index: index, value: Int(v))
                }
            ),
            range: mn...mx,
            step: 50,
            format: { "\(Int($0.rounded())) rpm" }
        )
    }

    // MARK: - Helpers / 中文：辅助方法

    private var rpmRange: ClosedRange<Double> {
        let lo = Double(viewModel.effectiveUnifiedMinRPM)
        let hi = Double(Swift.max(viewModel.effectiveUnifiedMaxRPM,
                                  viewModel.effectiveUnifiedMinRPM + 1))
        return lo...hi
    }

    private func responseLabel(for v: Double) -> String {
        if v <= 0.3 { return NSLocalizedString("popover.response.min_override",  comment: "") }
        if v <= 0.8 { return NSLocalizedString("popover.response.quiet",         comment: "") }
        if v <= 1.2 { return NSLocalizedString("popover.response.balanced",      comment: "") }
        if v <= 1.8 { return NSLocalizedString("popover.response.auto",          comment: "") }
        if v <= 2.3 { return NSLocalizedString("popover.response.performance",   comment: "") }
        if v <= 2.7 { return NSLocalizedString("popover.response.aggressive",    comment: "") }
        return NSLocalizedString("popover.response.max_override", comment: "")
    }

    /// One representative aggressiveness value per response label — the slider / 中文：One representative aggressiveness 值 per response label — the 滑杆
    /// snaps to exactly these notches instead of a continuous 0...3 range. / 中文：精确吸附到这些档位，而不是使用连续的 0...3 范围。
    private let responseSteps: [Double] = [0.0, 0.6, 1.0, 1.5, 2.0, 2.5, 3.0]

    /// Maps a stored aggressiveness value back to its notch index, using the / 中文：Maps a stored aggressiveness 值 back to its notch index, using the
    /// same thresholds as `responseLabel(for:)` so the round-trip is stable. / 中文：使用与 `responseLabel(for:)` 相同的阈值，确保往返转换稳定。
    private func responseIndex(for v: Double) -> Int {
        if v <= 0.3 { return 0 }
        if v <= 0.8 { return 1 }
        if v <= 1.2 { return 2 }
        if v <= 1.8 { return 3 }
        if v <= 2.3 { return 4 }
        if v <= 2.7 { return 5 }
        return 6
    }

    /// Resolves a slider position (0...6) to its representative value. / 中文：Resolves a 滑杆 position (0...6) to its representative 值.
    private func responseStep(_ sliderValue: Double) -> Double {
        let i = min(max(Int(sliderValue.rounded()), 0), responseSteps.count - 1)
        return responseSteps[i]
    }

    private func modeLabel(_ mode: ControlMode) -> String {
        switch mode {
        case .manual:
            return NSLocalizedString("popover.mode.manual", comment: "")
        case .automatic:
            return NSLocalizedString("popover.mode.auto", comment: "")
        case .system:
            return NSLocalizedString("popover.mode.system", comment: "")
        }
    }

    private func scheduleApply(_ value: Int) {
        manualApplyTask?.cancel()
        manualApplyTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { viewModel.setManualSpeed(value) }
        }
    }

    private func schedulePerFanApply(index: Int, value: Int) {
        perFanApplyTasks[index]?.cancel()
        perFanApplyTasks[index] = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                viewModel.setManualSpeedForFan(index: index, speed: value)
                perFanDraft[index] = nil
            }
        }
    }
}

// MARK: - LabeledSlider / 中文：带标签滑杆

/// Visual style for a labeled slider. / 中文：带标签滑杆的视觉风格.
/// - `neutral`: standard slider with a soft tint, for rpm / count / index. / 中文：标准滑杆 + 柔和着色，用于转速 / 计数 / 索引.
/// - `thermal`: gradient track spanning the temperature color range. / 中文：贯穿温度色谱的渐变轨道.
enum SliderAccent {
    case neutral
    case thermal
}

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double.Stride
    let format: (Double) -> String
    var accent: SliderAccent = .neutral

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Theme.text1(scheme))
                Spacer()
                Text(format(value))
                    .font(Theme.num(11.5, weight: .semibold))
                    .foregroundColor(Theme.text1(scheme))
            }
            Slider(value: $value, in: range, step: step)
                .tint(sliderTint)
        }
    }

    /// Thermal sliders glide through the temperature color range as the value / 中文：温度滑杆的着色随取值在温度色范围内滑动 (cool→critical)，
    /// moves; neutral sliders use a soft mono tint. The Slider's shape stays / 中文：非温度滑杆使用统一的温和单色着色。
    /// the system default so all sliders read as the same control. / 中文：滑杆外形完全沿用系统控件，所有滑杆视觉一致.
    private var sliderTint: Color {
        switch accent {
        case .thermal: return Theme.thermalColor(forTemperature: value, scheme: scheme)
        case .neutral: return Theme.sliderTint(scheme)
        }
    }
}
