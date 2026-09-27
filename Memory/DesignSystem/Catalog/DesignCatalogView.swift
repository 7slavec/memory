#if DEBUG
import SwiftUI

enum CatalogSection: String, CaseIterable, Identifiable {
    case foundations = "Основа", controls = "Элементы", records = "Записи", input = "Ввод", schedule = "Дата и время"
    var id: Self { self }
}

struct DesignCatalogView: View {
    @State private var section: CatalogSection = .records
    @State private var theme = "Обе"
    @State private var compact = true
    private let themes = ["Обе", "Светлая", "Тёмная"]
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Norka · Компоненты").font(.title2.weight(.semibold)).accessibilityIdentifier("catalog-title")
                    Spacer()
                    Text("Предложение 02").font(.caption).foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { selectors }
                    VStack(alignment: .leading, spacing: 12) { selectors }
                }
            }
            .padding(20)
            Divider()
            GeometryReader { available in
              ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: visibleSchemes.count == 2 && available.size.width >= 740 ? 2 : 1), alignment: .center, spacing: 24) {
                    ForEach(visibleSchemes, id: \.self) { dark in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(dark ? "Тёмная" : "Светлая").font(.headline)
                            CatalogBoard(section: section)
                                .environment(\.colorScheme, dark ? .dark : .light)
                                .frame(maxWidth: compact ? 390 : 620)
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
                .padding(.vertical, 24)
#if os(macOS)
                .padding(.horizontal, 24)
#endif
              }
            }
        }
        .background(Color.primary.opacity(0.035))
#if os(macOS)
        .frame(minWidth: 400, minHeight: 600)
#endif
    }
    @ViewBuilder private var selectors: some View {
        Picker("Раздел", selection: $section) { ForEach(CatalogSection.allCases) { Text($0.rawValue).tag($0) } }
            .pickerStyle(.menu).accessibilityIdentifier("catalog-section")
        Picker("Тема", selection: $theme) { ForEach(themes, id: \.self) { Text($0).tag($0) } }
            .pickerStyle(.segmented).frame(maxWidth: 260)
        Toggle("Узкий вид", isOn: $compact).toggleStyle(.switch).fixedSize()
    }
    private var visibleSchemes: [Bool] { theme == "Обе" ? [false, true] : [theme == "Тёмная"] }
}

struct CatalogBoard: View {
    @Environment(\.colorScheme) private var scheme
    let section: CatalogSection
    var body: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.sectionGap) {
            switch section {
            case .foundations: CatalogFoundations()
            case .controls: CatalogControlExamples()
            case .records: CatalogRecordExamples()
            case .input: CatalogInputExamples()
            case .schedule: CatalogScheduleDemo()
            }
        }
        .padding(.vertical, CatalogMetrics.pageInset)
        .padding(.horizontal, section == .schedule ? 0 : CatalogMetrics.pageInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(palette.text.color)
        .background(palette.background.color)
        .tint(palette.accent.color)
    }
    private var palette: CatalogPalette { .init(dark: scheme == .dark) }
}

private struct CatalogFoundations: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Large title").font(.caption).foregroundStyle(palette.secondary.color)
                Text("Важное — рядом").font(CatalogType.largeTitle)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("H1 · страница").font(.caption).foregroundStyle(palette.secondary.color)
                Text("Все записи").font(CatalogType.h1)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("H2 · раздел").font(.caption).foregroundStyle(palette.secondary.color)
                Text("Сегодня").font(CatalogType.h2)
            }
            Text("Body · Записать мысль, не теряя контекст.").font(CatalogType.body)
            Text("Caption · Ближайшее").font(CatalogType.caption).foregroundStyle(palette.secondary.color)
            Divider()
            Text("Цвет и текст").font(CatalogType.h2)
            HStack(spacing: 12) {
                swatch("Акцент", tone: .accent)
                swatch("Событие", tone: .event)
                swatch("Удаление", tone: .danger)
            }
            HStack(spacing: 12) {
                Text("Поверхность").font(CatalogType.caption).frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.surface.color, in: RoundedRectangle(cornerRadius: 12))
                Text("Контрол").font(CatalogType.caption).frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.inset.color, in: RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Отступы").font(CatalogType.h2)
                ForEach([4, 8, 12, 16, 24, 32, 40, 48], id: \.self) { value in
                    HStack(spacing: 12) {
                        Text("\(value)").font(.caption.monospacedDigit()).frame(width: 24, alignment: .leading)
                        Capsule().fill(palette.accent.color).frame(width: CGFloat(value) * 3, height: 8)
                    }
                }
            }
        }
    }
    private var palette: CatalogPalette { .init(dark: scheme == .dark) }
    private func swatch(_ title: String, tone: CatalogTone) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aa").font(.title2.weight(.semibold))
                .foregroundStyle(palette.foreground(for: tone).color)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(palette.fill(for: tone).color, in: RoundedRectangle(cornerRadius: 12))
            Text(title).font(CatalogType.caption)
        }.frame(maxWidth: .infinity)
    }
}

private struct CatalogControlExamples: View {
    @State private var hasDate = true
    @State private var event = false
    @State private var notifications = true
    @State private var reminder = "За 15 минут"
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Кнопки").font(CatalogType.h1)
            HStack(spacing: 16) {
                ForEach(CatalogControlSize.allCases) { size in
                    VStack(spacing: 4) {
                        CatalogIconButton(symbol: "plus", label: "Добавить \(size.rawValue)", size: size, tone: .primary) { status = "Нажата кнопка \(size.rawValue)" }
                        Text("\(size.rawValue) · \(Int(size.visual))").font(.caption)
                    }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack { actions }
                VStack(alignment: .leading) { actions }
            }
            Button("Недоступно") {}.buttonStyle(CatalogButtonStyle(tone: .primary)).disabled(true)
            Divider()
            Text("Плашки").font(CatalogType.h2)
            VStack(alignment: .leading, spacing: 4) {
                CatalogChip(title: event ? "Событие" : "Напоминание", tone: event ? .event : .accent) { event.toggle() }
                if hasDate {
                    CatalogChip(title: "Завтра · 09:00", action: { status = "Выбор даты — раздел «Дата и время»" }, onRemove: { hasDate = false })
                } else {
                    CatalogChip(title: "Добавить дату", icon: "plus") { hasDate = true }
                }
                CatalogChip(title: "Входящие", icon: "tray", tone: .neutral) { status = "Пример перехода во входящие" }
            }
            Divider()
            Text("Настройки").font(CatalogType.h2)
            VStack(spacing: 8) {
                CatalogSettingsRow(title: "Уведомления", icon: "bell") {
                    Toggle("Уведомления", isOn: $notifications).labelsHidden().toggleStyle(.switch)
                }
                CatalogSettingsRow(title: "Напомнить") {
                    CatalogChoiceControl(selection: $reminder, options: ["В момент", "За 15 минут", "За час", "За день"])
                }
                Button { status = "Пример перехода в архив" } label: {
                    CatalogSettingsRow(title: "Архив", icon: "archivebox") { Image(systemName: "chevron.right") }
                }.buttonStyle(.plain)
            }
            Button { status = "В каталоге выхода из аккаунта нет" } label: { Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right") }
                .buttonStyle(CatalogButtonStyle(tone: .danger, size: .large))
            Divider()
            Text("Основная шапка").font(CatalogType.h2)
            CatalogHeader()
            Text("Внутренняя шапка").font(CatalogType.h2)
            CatalogHeader(secondary: true)
            if !status.isEmpty { Text(status).font(.caption).accessibilityIdentifier("catalog-feedback") }
        }
    }
    @ViewBuilder private var actions: some View {
        Button("Сохранить") { status = "Пример нажатия; записи не создаются" }.buttonStyle(CatalogButtonStyle(tone: .primary))
        Button("Отмена") { status = "" }.buttonStyle(CatalogButtonStyle(tone: .neutral))
    }
}

private struct CatalogRecordExamples: View {
    @State private var completed = false
    @State private var giftCompleted = false
    @State private var selected: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            CatalogHeader()
            HStack {
                Text("Все записи").font(CatalogType.h1)
                Spacer(minLength: 8)
                CatalogIconButton(symbol: "tray", label: "Входящие", size: .medium) { selected = "Входящие" }
            }
            HStack {
                Image(systemName: "sun.max").accessibilityHidden(true)
                Text("Сегодня").font(CatalogType.h2)
                Spacer()
                Text("3").font(.subheadline.monospacedDigit())
            }
            VStack(spacing: 12) {
                CatalogRecordCard(title: "Отправить портфолио", details: "Добавить последние проекты", schedule: "Сегодня · 14:00", completed: completed, onOpen: { selected = "Отправить портфолио" }, onToggle: { completed.toggle() })
                CatalogRecordCard(title: "Вебинар по дизайну", details: "Обсудим работу с типографикой", schedule: "27–28 сент · 19:00–21:00", isEvent: true, onOpen: { selected = "Вебинар по дизайну" })
                CatalogRecordCard(title: "Подумать над идеей подарка", completed: giftCompleted, onOpen: { selected = "Подумать над идеей подарка" }, onToggle: { giftCompleted.toggle() })
            }
            if let selected { Text("Выбрано: \(selected)").font(.caption) }
        }
    }
}

private struct CatalogHeader: View {
    var secondary = false
    var body: some View {
        HStack {
            CatalogIconButton(symbol: secondary ? "arrow.left" : "rectangle.stack", label: secondary ? "Назад" : "Все записи") {}
            Spacer(minLength: 8)
            if secondary { Text("Запись").font(.headline) }
            else { Image("NorkaLogo").resizable().renderingMode(.template).scaledToFit().frame(width: 108, height: 32).accessibilityLabel("Norka") }
            Spacer(minLength: 8)
            CatalogIconButton(symbol: secondary ? "checkmark" : "person.fill", label: secondary ? "Готово" : "Профиль") {}
        }.frame(minHeight: CatalogMetrics.headerHeight)
    }
}

struct CatalogInputExamples: View {
    @State private var text = ""
    @State private var search = ""
    @State private var state = "Покой"
    @State private var sent = false
    @State private var showsExpansionNote = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Picker("Сфера", selection: $state) {
                ForEach(["Покой", "Слушает", "Думает"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
            GlassVoiceOrb(isListening: state == "Слушает", isProcessing: state == "Думает", isPulsing: false, size: 112)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
            Text(state == "Думает" ? "Вникаю в контекст…" : state == "Слушает" ? "Слушаю тебя" : "О чём напомнить?")
                .font(CatalogType.h1).frame(maxWidth: .infinity)
            CatalogComposerField(text: $text, onSend: { text = ""; sent = true }, onExpand: { showsExpansionNote = true })
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CatalogChip(title: "Завтра · 09:00") {}
                    CatalogChip(title: "Напоминание") {}
                }
            }
            CatalogSearchField(text: $search)
            if sent { Text("Пример отправлен. Настоящая запись не создавалась.").font(.caption) }
        }
        .alert("Образец поля ввода", isPresented: $showsExpansionNote) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Редактор не открывается: здесь проверяем только компоненты, без рабочих записей.")
        }
    }
    private var palette: CatalogPalette { .init(dark: scheme == .dark) }
}

#Preview("Компоненты · две темы") { DesignCatalogView() }
#endif
