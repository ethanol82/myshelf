import Cocoa

class StatusBarController {
    private let statusItem: NSStatusItem
    private var shelfWindowController: ShelfWindowController?
    private let shakeDetector = ShakeDetector()

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "tray", accessibilityDescription: "MyShelf")
        }

        setupMenu()
        setupShakeDetection()
    }

    // MARK: - Menu

    private func setupMenu() {
        let menu = NSMenu()

        let showItem = NSMenuItem(title: "Show Shelf", action: #selector(showShelf), keyEquivalent: "s")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit MyShelf", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Shake detection

    private func setupShakeDetection() {
        shakeDetector.onShakeDetected = { [weak self] mousePosition in
            print("👋 shake callback fired at \(mousePosition)") // DEBUG
            self?.showShelfNear(mousePosition)
        }
        print("📍 StatusBarController: onShakeDetected callback registered") // DEBUG

        // applicationDidFinishLaunching은 이미 메인 스레드 + 앱 완전 로드 후
        // DispatchQueue.main.async + [weak self] 패턴은 self가 해제된 뒤 조용히 리턴되는 버그 유발
        let trusted = AXIsProcessTrusted()
        print("🔐 AXIsProcessTrusted = \(trusted)") // DEBUG
        if trusted {
            print("🚀 StatusBarController: starting shake detector") // DEBUG
            shakeDetector.startMonitoring()
        } else {
            showAccessibilityAlert()
        }
    }

    private func showShelfNear(_ position: NSPoint) {
        if shelfWindowController == nil {
            shelfWindowController = ShelfWindowController()
        }
        shelfWindowController?.showShelf(at: position)
    }

    private func showAccessibilityAlert() {
        // LSUIElement 앱은 기본적으로 비활성 상태 — alert을 앞에 띄우려면 명시적 활성화 필요
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "손쉬운 사용 권한 필요"
        alert.informativeText = """
            드래그 중 마우스 흔들기 감지 기능을 사용하려면 손쉬운 사용 권한이 필요합니다.

            시스템 설정 > 개인 정보 보호 및 보안 > 손쉬운 사용에서 MyShelf를 허용한 뒤 앱을 재시작해주세요.
            """
        alert.addButton(withTitle: "시스템 설정 열기")
        alert.addButton(withTitle: "나중에")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Actions

    @objc private func showShelf() {
        if shelfWindowController == nil {
            shelfWindowController = ShelfWindowController()
        }
        shelfWindowController?.toggleShelf()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
