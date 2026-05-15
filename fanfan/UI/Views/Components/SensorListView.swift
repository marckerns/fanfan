//
//  File: SensorListView.swift / 文件：SensorListView.swift
//  Target: fanfan / 目标：fanfan
//
//  Created by haobin on 2026/5/15. / 创建者：haobin，日期：2026/5/15。
//  Description: Sensor list grouped by category. / 描述：按类别分组的传感器列表。
//

import SwiftUI

struct SensorListView: View {
    let sections: [SensorSection]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if sections.isEmpty {
            EmptySensorState()
        } else {
            VStack(spacing: 8) {
                ForEach(sections) { section in
                    sectionCard(section)
                }
            }
        }
    }

    private func sectionCard(_ section: SensorSection) -> some View {
        let accent = Theme.accent(for: section.maxTemperature, scheme: scheme)
        return VStack(spacing: 0) {
            HStack {
                Text(section.category.displayName.uppercased())
                    .font(Theme.label(10, weight: .semibold))
                    .tracking(0.4)
                    .foregroundColor(Theme.text3(scheme))
                Spacer()
                Text(String(format: "%.1f°", section.maxTemperature))
                    .font(Theme.num(11, weight: .semibold))
                    .foregroundColor(accent)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            ForEach(Array(section.sensors.enumerated()), id: \.element.id) { idx, sensor in
                if idx > 0 {
                    Rectangle()
                        .fill(Theme.separator(scheme))
                        .frame(height: 0.5)
                        .padding(.leading, 12)
                        .padding(.trailing, 12)
                }
                sensorRow(sensor)
            }
            .padding(.bottom, idxBottomPad)
        }
        .themedCard(scheme)
    }

    private var idxBottomPad: CGFloat { 2 }

    private func sensorRow(_ sensor: SensorReading) -> some View {
        let accent = Theme.accent(for: sensor.temperature, scheme: scheme)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(sensor.name)
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.text1(scheme))
                    .lineLimit(1)
                Text(sensor.id)
                    .font(Theme.num(9, weight: .medium))
                    .foregroundColor(Theme.text3(scheme))
                    .tracking(0.4)
            }
            Spacer()
            HeatBar(value: sensor.temperature, accent: accent, height: 3)
                .frame(width: 60)
            Text(String(format: "%.1f°", sensor.temperature))
                .font(Theme.num(12, weight: .semibold))
                .foregroundColor(Theme.text1(scheme))
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct EmptySensorState: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "thermometer.medium.slash")
                .font(.system(size: 20))
                .foregroundColor(Theme.text3(scheme))
            Text(NSLocalizedString("sensors.none", comment: ""))
                .font(.system(size: 11.5))
                .foregroundColor(Theme.text2(scheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}
