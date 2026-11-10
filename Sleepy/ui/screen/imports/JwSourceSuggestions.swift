import SwiftUI

struct JwSourceSuggestions: View {
    @Environment(\.localWakeUpColors) private var colors
    let importSourceJson: String
    var body: some View {
        if let metadata = JwSgSourceMetadata.read(importSourceJson), let config = metadata["config"] as? [String: Any] {
            VStack(alignment: .leading, spacing: 4) {
                if let adapter = metadata["adapter"] as? [String: Any] {
                    let name = adapter["name"] as? String ?? adapter["adapterId"] as? String ?? ""
                    if !name.isEmpty { Text(L10n.format("jw_source_entry", name)) }
                }
                if ["defaultClassDuration", "defaultBreakDuration", "firstDayOfWeek"].contains(where: { config[$0] != nil }) {
                    Text(L10n.t("jw_source_suggestions"))
                    if let minutes = JwSgSourceMetadata.strictInteger(config["defaultClassDuration"]) { Text(L10n.format("jw_source_class_minutes", String(minutes))) }
                    if let minutes = JwSgSourceMetadata.strictInteger(config["defaultBreakDuration"]) { Text(L10n.format("jw_source_break_minutes", String(minutes))) }
                    if let day = JwSgSourceMetadata.strictInteger(config["firstDayOfWeek"]) { Text(L10n.format("jw_source_first_weekday", DateUtils.localizedDay(day))) }
                }
            }.font(.system(size: 12)).foregroundColor(colors.onSurfaceVariant)
        }
    }
}
