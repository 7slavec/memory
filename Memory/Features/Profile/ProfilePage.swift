enum ProfilePage: String {
    case profile = "Профиль"
    case notifications = "Уведомления"
#if os(macOS)
    case quickCapture = "Быстрый ввод"
#endif
    case sync = "Синхронизация"
    case archive = "Архив"
    case voiceLab = "Voice Lab"
}
