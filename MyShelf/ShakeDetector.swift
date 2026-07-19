import Cocoa

class ShakeDetector {

    // MARK: - Tunable constants

    static let timeWindow: TimeInterval = 0.5      // 이 시간(초) 안에 감지된 방향 전환만 유효
    static let minDirectionChanges = 3              // 흔들기로 판정하는 방향 전환 최솟값
    static let minSegmentDistance: CGFloat = 40     // 방향 전환으로 인정하는 최소 X 이동 거리(pt)
    static let shakeCooldown: TimeInterval = 1.0    // 연속 감지 방지용 쿨다운(초)

    // MARK: -

    var onShakeDetected: ((NSPoint) -> Void)?

    private var isDragging = false
    private var monitors: [Any?] = []

    // Shake tracking state
    private var currentX: CGFloat?
    private var direction = 0           // 0=unknown, 1=right, -1=left
    private var localExtreme: CGFloat = 0
    private var reversals: [(x: CGFloat, time: TimeInterval)] = []
    private var lastShakeTime: TimeInterval = 0
    private var firstDragLogged = false // DEBUG

    // MARK: - Monitoring

    func startMonitoring() {
        print("✅ ShakeDetector: monitoring started, accessibility = \(AXIsProcessTrusted())") // DEBUG

        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.handleMouseDown()
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.handleMouseUp()
        }
        let drag = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.handleDrag(timestamp: event.timestamp)
        }
        monitors = [down, up, drag]
    }

    func stopMonitoring() {
        monitors.compactMap { $0 }.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }

    // MARK: - Event handlers

    private func handleMouseDown() {
        print("🖱 mouseDown at \(NSEvent.mouseLocation)") // DEBUG
        isDragging = true
        resetState()
    }

    private func handleMouseUp() {
        print("🖱 mouseUp, isDragging was \(isDragging)") // DEBUG
        isDragging = false
        resetState()
    }

    private func handleDrag(timestamp: TimeInterval) {
        guard isDragging else { return }

        if !firstDragLogged { // DEBUG
            print("🏃 first drag event received") // DEBUG
            firstDragLogged = true // DEBUG
        } // DEBUG

        let x = NSEvent.mouseLocation.x

        // 첫 샘플: 기준점 초기화
        guard let _ = currentX else {
            currentX = x
            localExtreme = x
            return
        }

        // 초기 방향 결정 (노이즈 무시를 위해 5pt 이상 이동 시에만)
        if direction == 0 {
            let delta = x - currentX!
            if abs(delta) > 5 {
                direction = delta > 0 ? 1 : -1
                localExtreme = x
            }
            currentX = x
            return
        }

        // 피크/밸리 추적 방식으로 방향 전환 감지
        if direction == 1 {
            localExtreme = max(localExtreme, x)
            if localExtreme - x >= Self.minSegmentDistance {
                recordReversal(at: localExtreme, time: timestamp)
                direction = -1
                localExtreme = x
            }
        } else {
            localExtreme = min(localExtreme, x)
            if x - localExtreme >= Self.minSegmentDistance {
                recordReversal(at: localExtreme, time: timestamp)
                direction = 1
                localExtreme = x
            }
        }
        currentX = x
    }

    // MARK: - Reversal tracking

    private func recordReversal(at x: CGFloat, time: TimeInterval) {
        reversals.append((x: x, time: time))
        reversals.removeAll { $0.time < time - Self.timeWindow }

        print("↔️ direction reversal #\(reversals.count) at x=\(Int(x))") // DEBUG

        guard reversals.count >= Self.minDirectionChanges else { return }
        guard time - lastShakeTime >= Self.shakeCooldown else {
            reversals.removeAll()
            return
        }

        let count = reversals.count // DEBUG
        let duration = time - (reversals.first?.time ?? time) // DEBUG
        print("🎯 SHAKE DETECTED! reversals=\(count), duration=\(String(format: "%.2f", duration))s") // DEBUG

        lastShakeTime = time
        let mousePos = NSEvent.mouseLocation
        reversals.removeAll()

        DispatchQueue.main.async { [weak self] in
            print("📞 calling onShakeDetected callback") // DEBUG
            self?.onShakeDetected?(mousePos)
        }
    }

    private func resetState() {
        currentX = nil
        direction = 0
        localExtreme = 0
        reversals = []
        firstDragLogged = false // DEBUG
    }
}
