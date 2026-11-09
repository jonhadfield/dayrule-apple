import SwiftUI

#if DEBUG
/// Static layouts for design-capture screenshots (PLAN polish: editor rule, Mac
/// sidebar, Move, paper Add, token table). Avoids AppKit text fields / OutlineList
/// so `ImageRenderer` can flatten them. Not shown in the shipping UI.
enum DesignCaptures {
    struct EditorCapture: View {
        @Environment(\.colorScheme) private var colorScheme
        var body: some View {
            let colors = DayruleColors.resolve(colorScheme: colorScheme)
            VStack(alignment: .leading, spacing: 0) {
                Text("To-do")
                    .font(DayruleType.sheetTitle)
                    .foregroundStyle(colors.text)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { colors.hairline.frame(height: 1) }

                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    Text("Paint the hallway")
                        .dayruleRowTitle()
                        .foregroundStyle(colors.text)
                    Text("Sample the terracotta swatches first.")
                        .dayruleRowTitle()
                        .foregroundStyle(colors.textSecondary)
                        .frame(minHeight: 120, alignment: .topLeading)
                }
                .padding(Tokens.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.sidebar.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous)
                        .strokeBorder(colors.hairline, lineWidth: 1)
                )
                .overlay(alignment: .leading) {
                    colors.accent
                        .frame(width: 3)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: Tokens.radiusCard,
                                bottomLeadingRadius: Tokens.radiusCard,
                                style: .continuous
                            )
                        )
                }
                .padding(Tokens.Space.l)

                Spacer(minLength: 0)
            }
            .frame(width: 440, height: 520, alignment: .topLeading)
            .background(colors.bg)
            .environment(\.dayruleDenseLayout, true)
        }
    }

    struct SidebarCapture: View {
        @Environment(\.colorScheme) private var colorScheme
        var body: some View {
            let colors = DayruleColors.resolve(colorScheme: colorScheme)
            let names: [(String, String, Bool)] = [
                ("tray", "Inbox", true),
                ("circle.circle", "Today", false),
                ("calendar", "Scheduled", false),
                ("checklist", "Backlog", false),
            ]
            VStack(alignment: .leading, spacing: 0) {
                Text("Dayrule")
                    .font(DayruleType.pageTitle)
                    .tracking(DayruleType.titleTracking)
                    .foregroundStyle(colors.text)
                    .padding(.horizontal, Tokens.Space.l)
                    .padding(.vertical, Tokens.Space.m)
                ForEach(names, id: \.1) { icon, title, selected in
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(selected ? colors.accent : .clear)
                            .frame(width: 3)
                            .padding(.trailing, 8)
                        Image(systemName: icon)
                            .foregroundStyle(selected ? colors.accent : colors.textSecondary)
                            .frame(width: 22)
                        Text(title)
                            .dayruleRowTitle()
                            .foregroundStyle(colors.text)
                        Spacer()
                    }
                    .padding(.horizontal, Tokens.Space.m)
                    .frame(height: Tokens.rowHeightDesktop)
                    .background(selected ? colors.selectedRow : Color.clear)
                }
                Text("15pt body · terracotta selection")
                    .font(DayruleType.meta)
                    .foregroundStyle(colors.textSecondary)
                    .padding(Tokens.Space.m)
            }
            .frame(width: 260, height: 320, alignment: .topLeading)
            .background(colors.sidebar)
            .environment(\.dayruleDenseLayout, true)
        }
    }

    struct MoveCapture: View {
        @Environment(\.colorScheme) private var colorScheme
        var body: some View {
            let colors = DayruleColors.resolve(colorScheme: colorScheme)
            VStack(alignment: .leading, spacing: 0) {
                Text("Move")
                    .font(DayruleType.sheetTitle)
                    .foregroundStyle(colors.text)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { colors.hairline.frame(height: 1) }

                moveRow("tray", "Inbox", tint: colors.textSecondary, selected: true, colors: colors)
                moveRow("checklist", "No project or area", tint: colors.ready, selected: false, colors: colors)
                Text("PROJECTS AND AREAS")
                    .font(DayruleType.sectionHeader)
                    .foregroundStyle(colors.textSecondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, Tokens.Space.l)
                    .padding(.top, Tokens.Space.m)
                    .padding(.bottom, Tokens.Space.xs)
                moveRow("shippingbox", "Home", tint: colors.textSecondary, selected: false, colors: colors, indent: false)
                HStack(spacing: Tokens.Space.s) {
                    Color.clear.frame(width: Tokens.Space.l)
                    Circle()
                        .stroke(colors.hairline, lineWidth: 2)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .trim(from: 0, to: 0.25)
                                .stroke(colors.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        )
                    Text("Renovate")
                        .dayruleRowTitle()
                        .foregroundStyle(colors.text)
                    Spacer()
                }
                .padding(.horizontal, Tokens.Space.l)
                .frame(height: Tokens.rowHeightDesktop)
                .overlay(alignment: .bottom) { colors.hairline.frame(height: 1) }

                Spacer(minLength: 0)
            }
            .frame(width: 420, height: 480, alignment: .topLeading)
            .background(colors.bg)
        }

        private func moveRow(
            _ systemImage: String,
            _ title: String,
            tint: Color,
            selected: Bool,
            colors: DayruleColors,
            indent: Bool = false
        ) -> some View {
            HStack(spacing: Tokens.Space.s) {
                if indent { Color.clear.frame(width: Tokens.Space.l) }
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 20)
                Text(title)
                    .dayruleRowTitle()
                    .foregroundStyle(colors.text)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(colors.accent)
                }
            }
            .padding(.horizontal, Tokens.Space.l)
            .frame(height: Tokens.rowHeightDesktop)
            .overlay(alignment: .bottom) { colors.hairline.frame(height: 1) }
        }
    }

    struct PaperAddCapture: View {
        @Environment(\.colorScheme) private var colorScheme
        @ScaledMetric(relativeTo: .body) private var checkboxDiameter: CGFloat = 20
        var body: some View {
            let colors = DayruleColors.resolve(colorScheme: colorScheme)
            let disc = checkboxDiameter + 4
            let slot = max(Tokens.rowLeadingSlot, checkboxDiameter + 8)
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                Text("Today")
                    .font(DayruleType.pageTitle)
                    .tracking(DayruleType.titleTracking)
                    .foregroundStyle(colors.text)
                RuledRow {
                    HStack(spacing: Tokens.rowGlyphSpacing) {
                        Circle()
                            .strokeBorder(colors.checkboxBorder, lineWidth: 1.5)
                            .frame(width: checkboxDiameter, height: checkboxDiameter)
                            .frame(width: slot, height: slot)
                        Text("Existing to-do")
                            .dayruleRowTitle()
                            .foregroundStyle(colors.text)
                        Spacer()
                    }
                }
                RuledRow {
                    HStack(spacing: Tokens.rowGlyphSpacing) {
                        Image(systemName: "plus")
                            .font(.system(size: disc * 0.55, weight: .semibold))
                            .foregroundStyle(colors.bg)
                            .frame(width: disc, height: disc)
                            .background(colors.accent, in: Circle())
                            .frame(width: slot, height: slot)
                        Text("Add")
                            .dayruleRowTitle()
                            .foregroundStyle(colors.textSecondary)
                        Spacer()
                    }
                }
                Text("Native paper + Add (not the web floating pill)")
                    .font(DayruleType.meta)
                    .foregroundStyle(colors.textSecondary)
            }
            .padding(Tokens.Space.l)
            .frame(width: 420, height: 280, alignment: .topLeading)
            .background(colors.bg)
        }
    }

    struct TokensCapture: View {
        @Environment(\.colorScheme) private var colorScheme
        var body: some View {
            let colors = DayruleColors.resolve(colorScheme: colorScheme)
            let swatches: [(String, Color, String)] = [
                ("paper", colors.bg, "#F7F3EC / #1B1814"),
                ("sidebar", colors.sidebar, "#EFE8DC / #221E19"),
                ("accent", colors.accent, "#AA4628 / #E07A55"),
                ("scheduled", colors.scheduled, "#8E5A18 / #D9A14E"),
                ("ready", colors.ready, "#4F6B3A / #8FAE74"),
                ("later", colors.later, "#5D6771 / #9AA6B2"),
                ("deadline", colors.deadline, "#B3261E / #E5735F"),
            ]
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text("tokens.css (PLAN §5.1)")
                    .font(DayruleType.sheetTitle)
                    .foregroundStyle(colors.text)
                Text("Binary layout at 900px · sidebar ~260px · no 600px drawer")
                    .font(DayruleType.meta)
                    .foregroundStyle(colors.textSecondary)
                ForEach(swatches, id: \.0) { name, color, hex in
                    HStack(spacing: Tokens.Space.m) {
                        RoundedRectangle(cornerRadius: Tokens.radiusRow)
                            .fill(color)
                            .frame(width: 36, height: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: Tokens.radiusRow)
                                    .strokeBorder(colors.hairline, lineWidth: 1)
                            )
                        Text(name)
                            .dayruleRowTitle()
                            .foregroundStyle(colors.text)
                            .frame(width: 88, alignment: .leading)
                        Text(hex)
                            .font(DayruleType.meta.monospaced())
                            .foregroundStyle(colors.textSecondary)
                    }
                }
            }
            .padding(Tokens.Space.l)
            .frame(width: 480, height: 360, alignment: .topLeading)
            .background(colors.bg)
        }
    }

    struct MenuCapture: View {
        @Environment(\.colorScheme) private var colorScheme
        var body: some View {
            let colors = DayruleColors.resolve(colorScheme: colorScheme)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Tokens.Space.l) {
                    Text("Dayrule").fontWeight(.semibold)
                    Text("Edit")
                    Text("View")
                    Spacer()
                }
                .dayruleRowTitle()
                .foregroundStyle(colors.text)
                .padding(.horizontal, Tokens.Space.m)
                .frame(height: 28)
                .background(colors.sidebar)
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    menuRow("Settings…", shortcut: "⌘,", colors: colors)
                    menuRow("Lock", shortcut: "⇧⌘L", colors: colors)
                    Divider().background(colors.hairline)
                    menuRow("New To-Do", shortcut: "⌘N", colors: colors)
                    menuRow("New Project", shortcut: "⌥⌘N", colors: colors)
                    menuRow("New Area", shortcut: "⌥⌘A", colors: colors)
                    Divider().background(colors.hairline)
                    menuRow("Undo", shortcut: "⌘Z", colors: colors)
                    menuRow("Redo", shortcut: "⇧⌘Z", colors: colors)
                    menuRow("Find…", shortcut: "⌘F", colors: colors)
                    menuRow("Move to Trash", shortcut: "⌫", colors: colors)
                }
                .padding(Tokens.Space.m)
                .background(colors.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.radiusPopover)
                        .strokeBorder(colors.hairline, lineWidth: 1)
                )
                .padding(Tokens.Space.m)
            }
            .frame(width: 320, height: 280, alignment: .topLeading)
            .background(colors.bg)
        }

        private func menuRow(_ title: String, shortcut: String, colors: DayruleColors) -> some View {
            HStack {
                Text(title).foregroundStyle(colors.text)
                Spacer()
                Text(shortcut).foregroundStyle(colors.textSecondary)
            }
            .dayruleRowTitle()
        }
    }
}
#endif
