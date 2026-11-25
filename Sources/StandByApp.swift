//
//  StandByApp.swift
//  Mode Veille (StandBy) sans recharge – avec page Musique
//

import SwiftUI
import Combine
import MediaPlayer

// MARK: - ═══════════════ POINT D'ENTRÉE ═══════════════

@main
struct StandByApp: App {
    var body: some Scene {
        WindowGroup {
            StandByView()
        }
    }
}

// MARK: - ═══════════════ VUE PRINCIPALE ═══════════════

struct StandByView: View {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var battery = BatteryMonitor()
    @StateObject private var music = MusicController()

    @State private var page = 0
    @State private var nightMode = false
    @State private var manualOverride = false
    @State private var shift: CGSize = .zero

    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var tint: Color {
        nightMode ? Color(red: 0.85, green: 0.1, blue: 0.1) : .white
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $page) {
                DigitalClockPage(tint: tint).tag(0)
                AnalogClockPage(tint: tint).padding(30).tag(1)
                InfoPage(tint: tint, battery: battery).tag(2)
                MusicPage(tint: tint, isNight: nightMode, music: music).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(shift)
        }
        // Double tap : active / désactive le mode nuit manuellement
        .onTapGesture(count: 2) {
            manualOverride = true
            withAnimation { nightMode.toggle() }
        }
        // Chaque minute : décalage anti-marquage OLED + mode nuit automatique
        .onReceive(minuteTimer) { _ in
            withAnimation(.easeInOut(duration: 2)) {
                shift = CGSize(width: .random(in: -6...6), height: .random(in: -6...6))
            }
            updateAutoNightMode()
        }
        .onAppear {
            setIdleTimerDisabled(true)
            updateAutoNightMode()
        }
        .onDisappear { setIdleTimerDisabled(false) }
        // Empêche la mise en veille uniquement quand l'app est au premier plan
        .onChange(of: scenePhase) { _, phase in
            setIdleTimerDisabled(phase == .active)
        }
        // Bascule automatiquement sur la page Musique quand un morceau démarre
        .onChange(of: music.isPlaying) { _, playing in
            if playing { withAnimation { page = 3 } }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }

    private func updateAutoNightMode() {
        guard !manualOverride else { return }
        let hour = Calendar.current.component(.hour, from: .now)
        withAnimation { nightMode = (hour >= 22 || hour < 7) }
    }
}

// MARK: - ═══════════════ PAGE 1 : HORLOGE NUMÉRIQUE ═══════════════

struct DigitalClockPage: View {
    let tint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let c = Calendar.current.dateComponents([.hour, .minute], from: context.date)
            VStack(spacing: 0) {
                Text(String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0))
                    .font(.system(size: 180, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)
                Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.title2.weight(.semibold))
                    .textCase(.uppercase)
                    .opacity(0.6)
            }
            .foregroundStyle(tint)
            .padding()
        }
    }
}

// MARK: - ═══════════════ PAGE 2 : HORLOGE ANALOGIQUE ═══════════════

struct AnalogClockPage: View {
    let tint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Canvas { ctx, size in
                let r = min(size.width, size.height) / 2 * 0.95
                let c = CGPoint(x: size.width / 2, y: size.height / 2)

                // Graduations
                for i in 0..<60 {
                    let a = Double(i) / 60 * 2 * .pi
                    let major = i % 5 == 0
                    var p = Path()
                    p.move(to: clockPoint(c, r, a))
                    p.addLine(to: clockPoint(c, r - (major ? 18 : 8), a))
                    ctx.stroke(p, with: .color(tint.opacity(major ? 1 : 0.35)),
                               style: StrokeStyle(lineWidth: major ? 4 : 2, lineCap: .round))
                }

                // Aiguilles
                let comp = Calendar.current.dateComponents([.hour, .minute, .second], from: context.date)
                let h = Double((comp.hour ?? 0) % 12)
                let m = Double(comp.minute ?? 0)
                let s = Double(comp.second ?? 0)

                drawHand(ctx, c, r * 0.5,  (h + m / 60) / 12, 8, tint)
                drawHand(ctx, c, r * 0.78, (m + s / 60) / 60, 5, tint)
                drawHand(ctx, c, r * 0.88, s / 60, 2, .orange)

                // Centre
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)),
                         with: .color(.orange))
            }
        }
    }
}

private func clockPoint(_ c: CGPoint, _ len: CGFloat, _ angle: Double) -> CGPoint {
    CGPoint(x: c.x + len * sin(angle), y: c.y - len * cos(angle))
}

private func drawHand(_ ctx: GraphicsContext, _ c: CGPoint, _ len: CGFloat,
                      _ fraction: Double, _ width: CGFloat, _ color: Color) {
    var p = Path()
    p.move(to: c)
    p.addLine(to: clockPoint(c, len, fraction * 2 * .pi))
    ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
}

// MARK: - ═══════════════ PAGE 3 : CALENDRIER + BATTERIE ═══════════════

struct InfoPage: View {
    let tint: Color
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 60) {
                // Calendrier
                VStack {
                    Text(context.date.formatted(.dateTime.weekday(.wide)))
                        .font(.title.weight(.bold))
                        .foregroundStyle(.red)
                        .textCase(.uppercase)
                    Text(context.date.formatted(.dateTime.day()))
                        .font(.system(size: 120, weight: .bold, design: .rounded))
                    Text(context.date.formatted(.dateTime.month(.wide).year()))
                        .font(.title3)
                        .opacity(0.6)
                }

                // Batterie
                VStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(tint.opacity(0.2), lineWidth: 14)
                        Circle()
                            .trim(from: 0, to: CGFloat(max(battery.level, 0)))
                            .stroke(battery.level < 0.2 ? Color.red : Color.green,
                                    style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: battery.isCharging ? "bolt.fill" : "iphone")
                            .font(.system(size: 40))
                    }
                    .frame(width: 140, height: 140)

                    Text(battery.level >= 0 ? "\(Int(battery.level * 100)) %" : "--")
                        .font(.title.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(tint)
        }
    }
}

// MARK: - ═══════════════ PAGE 4 : MUSIQUE ═══════════════

struct MusicPage: View {
    let tint: Color
    let isNight: Bool
    @ObservedObject var music: MusicController

    var body: some View {
        ZStack {
            // Fond flouté avec la pochette
            if let art = music.artwork {
                Image(uiImage: art)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 60)
                    .opacity(isNight ? 0.1 : 0.35)
                    .ignoresSafeArea()
            }

            if !music.authorized {
                VStack(spacing: 12) {
                    Image(systemName: "music.note").font(.system(size: 50))
                    Text("Autorisez l'accès à Musique dans Réglages")
                        .font(.title3)
                }
                .foregroundStyle(tint)
            } else {
                HStack(spacing: 40) {
                    artworkView
                    VStack(alignment: .leading, spacing: 18) {
                        infos
                        progressBar
                        controls
                        VolumeSlider().frame(height: 30)
                    }
                    .frame(maxWidth: 380)
                }
                .padding(30)
                .foregroundStyle(tint)
            }
        }
    }

    // Pochette
    private var artworkView: some View {
        Group {
            if let art = music.artwork {
                Image(uiImage: art).resizable().scaledToFit()
            } else {
                ZStack {
                    Color.gray.opacity(0.25)
                    Image(systemName: "music.note")
                        .font(.system(size: 70))
                        .opacity(0.6)
                }
            }
        }
        .frame(width: 230, height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(radius: 20)
        .opacity(isNight ? 0.5 : 1)
    }

    // Titre + artiste (+ bouton pour ouvrir Musique si rien ne joue)
    private var infos: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(music.title)
                .font(.title.weight(.bold))
                .lineLimit(1)
            if music.hasItem {
                Text(music.artist)
                    .font(.title3)
                    .opacity(0.6)
                    .lineLimit(1)
            } else {
                Button("Ouvrir Musique") {
                    if let url = URL(string: "music://") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.title3)
            }
        }
    }

    // Barre de progression
    private var progressBar: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let current = music.currentTime
            let ratio = music.duration > 0 ? current / music.duration : 0
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(tint.opacity(0.2))
                        Capsule().fill(tint)
                            .frame(width: geo.size.width * CGFloat(min(max(ratio, 0), 1)))
                    }
                }
                .frame(height: 6)
                HStack {
                    Text(formatTime(current))
                    Spacer()
                    Text("-" + formatTime(max(music.duration - current, 0)))
                }
                .font(.caption.monospacedDigit())
                .opacity(0.6)
            }
        }
    }

    // Boutons de contrôle
    private var controls: some View {
        HStack(spacing: 50) {
            Button { music.previous() } label: {
                Image(systemName: "backward.fill")
            }
            Button { music.togglePlay() } label: {
                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
                    .frame(width: 50)
            }
            Button { music.next() } label: {
                Image(systemName: "forward.fill")
            }
        }
        .font(.system(size: 30))
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// Curseur de volume système
struct VolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.tintColor = .white
        return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - ═══════════════ SUIVI DE LA BATTERIE ═══════════════

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published var level: Float = -1
    @Published var isCharging = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        update()
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification))
            .sink { [weak self] _ in
                Task { @MainActor in self?.update() }
            }
            .store(in: &cancellables)
    }

    private func update() {
        level = UIDevice.current.batteryLevel
        let state = UIDevice.current.batteryState
        isCharging = (state == .charging || state == .full)
    }
}

// MARK: - ═══════════════ CONTRÔLEUR DE L'APP MUSIQUE ═══════════════

@MainActor
final class MusicController: ObservableObject {
    private let player = MPMusicPlayerController.systemMusicPlayer
    private var cancellables = Set<AnyCancellable>()

    @Published var authorized = false
    @Published var hasItem = false
    @Published var title = "Aucune lecture"
    @Published var artist = ""
    @Published var artwork: UIImage?
    @Published var isPlaying = false
    @Published var duration: TimeInterval = 0

    init() {
        Task {
            let status = await MPMediaLibrary.requestAuthorization()
            authorized = (status == .authorized)
            if authorized { start() }
        }
    }

    private func start() {
        player.beginGeneratingPlaybackNotifications()
        NotificationCenter.default
            .publisher(for: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player)
            .merge(with: NotificationCenter.default
                .publisher(for: .MPMusicPlayerControllerPlaybackStateDidChange, object: player))
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &cancellables)
        refresh()
    }

    func refresh() {
        let item = player.nowPlayingItem
        hasItem   = (item != nil)
        title     = item?.title ?? "Aucune lecture"
        artist    = item?.artist ?? ""
        artwork   = item?.artwork?.image(at: CGSize(width: 600, height: 600))
        duration  = item?.playbackDuration ?? 0
        isPlaying = (player.playbackState == .playing)
    }

    var currentTime: TimeInterval {
        let t = player.currentPlaybackTime
        return t.isNaN ? 0 : t
    }

    func togglePlay() { isPlaying ? player.pause() : player.play() }
    func next()       { player.skipToNextItem() }
    func previous() {
        // Comme Apple : si plus de 3 s écoulées, on revient au début du morceau
        currentTime > 3 ? player.skipToBeginning() : player.skipToPreviousItem()
    }
}
