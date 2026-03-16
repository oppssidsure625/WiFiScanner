/*
Update history:
・v1.0.1 2026/03/16 Add channel width support
・v1.0.0 2026/03/16 First release
*/
import SwiftUI
import CoreWLAN
import CoreLocation
import Combine
import UniformTypeIdentifiers

// --- 1. Location Manager ---
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        manager.delegate = self
    }
    
    func requestPermission() {
        DispatchQueue.main.async {
            self.manager.requestAlwaysAuthorization()
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
        }
    }
}

// --- 2. WiFi Row View ---
struct WifiRowView: View {
    let item: WifiNetwork
    let isConnected: Bool
    let copyAction: (String) -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if isConnected {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 14))
                }
                Text(item.ssid).font(.system(size: 15, weight: .bold)).lineLimit(1).foregroundColor(isConnected ? .green : .primary)
                Button(action: { copyAction(item.ssid) }) {
                    Image(systemName: "doc.on.doc").font(.system(size: 11))
                }.buttonStyle(.plain)
            }
            .frame(width: 200, alignment: .leading).clipped()
            
            Text(item.standard).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary).frame(width: 125, alignment: .leading).clipped()

            HStack(spacing: 4) {
                Text(item.bssid).font(.system(size: 13, weight: .regular, design: .monospaced)).foregroundColor(.secondary).lineLimit(1)
                Button(action: { copyAction(item.bssid) }) {
                    Image(systemName: "doc.on.doc").font(.system(size: 11))
                }.buttonStyle(.plain)
            }
            .frame(width: 180, alignment: .leading).clipped()
            
            Text(item.mode).font(.system(size: 11, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 3)
                .background(item.mode == "Infrastructure" ? Color.gray.opacity(0.1) : Color.orange.opacity(0.2))
                .cornerRadius(4).frame(width: 100, alignment: .leading).clipped()

            Text(item.bandString).font(.system(size: 13, weight: .bold)).foregroundColor(item.bandColor).frame(width: 70, alignment: .leading).clipped()
            
            // バンド幅 (Width)
            Text(item.channelWidthString)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(item.channelWidthString.contains("320") ? .purple : .primary)
                .frame(width: 75, alignment: .center).clipped()
            
            Text("\(item.channel)").font(.system(size: 14, weight: .bold, design: .monospaced)).frame(width: 50, alignment: .center).clipped()
            
            HStack(spacing: 4) {
                Image(systemName: item.authType == "Enterprise" ? "lock.shield.fill" : (item.security == "OPEN" ? "lock.open.fill" : "lock.fill"))
                    .font(.system(size: 10))
                Text(item.security).font(.system(size: 12, weight: .bold))
                if !item.authType.isEmpty {
                    Text(item.authType).font(.system(size: 10, weight: .light)).opacity(0.9)
                }
            }
            .lineLimit(1).padding(.horizontal, 8).padding(.vertical, 4)
            .background(item.securityBgColor.opacity(0.15)).foregroundColor(item.securityBgColor)
            .cornerRadius(6).frame(width: 150, alignment: .leading).clipped()
            
            Spacer(minLength: 10)
            
            HStack(spacing: 8) {
                Image(systemName: "wifi", variableValue: item.wifiStrengthValue)
                Text("\(item.rssi) dBm").font(.system(size: 14, weight: .bold, design: .monospaced)).lineLimit(1).fixedSize()
            }
            .foregroundColor(item.rssi > -60 ? .green : (item.rssi > -80 ? .orange : .red))
            .frame(width: 95, alignment: .trailing).clipped()
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering } }
    }
}

// --- 3. Data Model ---
struct WifiNetwork: Identifiable, Equatable, Hashable {
    var id: String { bssid }
    let ssid, bssid: String
    let rssi, channel: Int
    let bandValue: Double
    let bandString, channelWidthString, security, authType, mode, standard: String
    let securityBgColor, bandColor: Color
    let wifiStrengthValue: Double

    init(raw: CWNetwork) {
        self.bssid = raw.bssid?.uppercased() ?? "00:00:00:00:00:00"
        self.ssid = raw.ssid ?? "Unknown"
        self.rssi = raw.rssiValue
        self.channel = raw.wlanChannel?.channelNumber ?? 0
        self.mode = raw.ibss ? "Ad Hoc" : "Infrastructure"
        
        // 規格 (Standard) 判定
        // 注: mode11be は最新のSDKでのみ提供。未定義の場合は rawValue 等での判定が必要。
        if raw.supportsPHYMode(.mode11ax) { self.standard = "Wi-Fi 6 (11ax)" }
        else if raw.supportsPHYMode(.mode11ac) { self.standard = "Wi-Fi 5 (11ac)" }
        else if raw.supportsPHYMode(.mode11n) { self.standard = "Wi-Fi 4 (11n)" }
        else if raw.supportsPHYMode(.mode11g) { self.standard = "Wi-Fi 3 (11g)" }
        else if raw.supportsPHYMode(.mode11a) { self.standard = "Wi-Fi 2 (11a)" }
        else if raw.supportsPHYMode(.mode11b) { self.standard = "Wi-Fi 1 (11b)" }
        else {
            // Wi-Fi 7 などの新しい規格が "Legacy" に落ちるのを防ぐための将来用フック
            self.standard = "Wi-Fi 7/Next"
        }
        
        // 周波数帯 (Band)
        switch raw.wlanChannel?.channelBand {
            case .band2GHz: self.bandValue = 2.4
            case .band5GHz: self.bandValue = 5.0
            case .band6GHz: self.bandValue = 6.0
            default: self.bandValue = 0.0
        }
        self.bandString = bandValue > 0 ? "\(bandValue)GHz" : "--"
        self.bandColor = bandValue == 6.0 ? .purple : (bandValue == 5.0 ? .blue : .primary)
        
        // バンド幅 (Channel Width)
        switch raw.wlanChannel?.channelWidth {
            case .width20MHz: self.channelWidthString = "20MHz"
            case .width40MHz: self.channelWidthString = "40MHz"
            case .width80MHz: self.channelWidthString = "80MHz"
            case .width160MHz: self.channelWidthString = "160MHz"
            default:
                // SDKが320MHzをサポートしていない場合の暫定処理（rawValueなどから推測可能な場合がある）
                self.channelWidthString = "320MHz?"
        }
        
        // セキュリティ
        if raw.supportsSecurity(.wpa3Enterprise) { self.security = "WPA3"; self.authType = "Enterprise"; self.securityBgColor = .purple }
        else if raw.supportsSecurity(.wpa3Personal) { self.security = "WPA3"; self.authType = "Personal"; self.securityBgColor = .green }
        else if raw.supportsSecurity(.wpa2Enterprise) { self.security = "WPA2"; self.authType = "Enterprise"; self.securityBgColor = .indigo }
        else if raw.supportsSecurity(.wpa2Personal) { self.security = "WPA2"; self.authType = "Personal"; self.securityBgColor = .blue }
        else if raw.supportsSecurity(.wpaPersonal) { self.security = "WPA"; self.authType = "Personal"; self.securityBgColor = .orange }
        else if raw.supportsSecurity(.dynamicWEP) { self.security = "WEP"; self.authType = "Legacy"; self.securityBgColor = .gray }
        else if raw.supportsSecurity(.none) { self.security = "OPEN"; self.authType = ""; self.securityBgColor = .red }
        else { self.security = "Other"; self.authType = ""; self.securityBgColor = .secondary }
        
        self.wifiStrengthValue = Swift.max(0.1, Swift.min(1.0, (Double(rssi) + 100.0) / 60.0))
    }
}

// --- 4. Main Content View ---
struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var allNetworks: [WifiNetwork] = []
    @State private var lastUpdateTime: String = ""
    @State private var currentSSID: String? = nil
    @State private var isScanning = false
    @State private var isAutoScanEnabled = false
    @State private var searchText: String = ""
    @State private var sortKey: SortKey = .rssi
    @State private var isAscending: Bool = false
    @State private var selection = Set<String>()
    
    @State private var selectedBand: BandFilter = .all
    @State private var selectedSecurity: SecurityFilter = .all
    @State private var selectedRSSI: RSSIFilter = .all
    
    @State private var showToast = false
    @State private var toastMessage = ""
    
    let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    enum BandFilter: String, CaseIterable { case all = "All", band2G = "2.4GHz", band5G = "5GHz", band6G = "6GHz" }
    enum SecurityFilter: String, CaseIterable { case all = "Any Security", wpa3 = "WPA3", wpa2 = "WPA2", wpa = "WPA", wep = "WEP", open = "OPEN" }
    enum RSSIFilter: String, CaseIterable { case all = "Any Strength", strong = ">-60", fair = ">-80" }
    enum SortKey { case ssid, standard, bssid, band, channel, rssi, width }

    var filteredNetworks: [WifiNetwork] {
        allNetworks.filter { net in
            let matchBand = (selectedBand == .all) || (selectedBand == .band2G && net.bandValue == 2.4) || (selectedBand == .band5G && net.bandValue == 5.0) || (selectedBand == .band6G && net.bandValue == 6.0)
            let matchSecurity = (selectedSecurity == .all) || (net.security == selectedSecurity.rawValue)
            let matchRSSI = (selectedRSSI == .all) || (selectedRSSI == .strong && net.rssi > -60) || (selectedRSSI == .fair && net.rssi > -80)
            let matchSearch = searchText.isEmpty || net.ssid.localizedCaseInsensitiveContains(searchText) || net.bssid.localizedCaseInsensitiveContains(searchText)
            return matchBand && matchSecurity && matchRSSI && matchSearch
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                headerView
                filterPanel
                columnHeaders
                Divider()
                
                List(filteredNetworks, selection: $selection) { item in
                    WifiRowView(item: item,
                                isConnected: item.ssid == currentSSID,
                                copyAction: { text in
                                    copyToClipboard(text)
                                    triggerToast(message: "Copied: \(text)")
                                })
                        .tag(item.bssid)
                        .onTapGesture {
                            let isCommandPressed = NSEvent.modifierFlags.contains(.command)
                            handleSelectionToggle(for: item.bssid, isCommandPressed: isCommandPressed)
                        }
                }
                .listStyle(.inset)
                .onCommand(#selector(NSText.copy(_:))) {
                    copySelectedItemsAsCSV()
                    triggerToast(message: "Selected items copied as CSV")
                }
                .onCommand(#selector(NSResponder.selectAll(_:))) {
                    selection = Set(filteredNetworks.map { $0.bssid })
                }
            }
            
            VStack {
                Spacer()
                if showToast {
                    Text(toastMessage)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.black.opacity(0.75))
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 20)
                }
            }
            .animation(.spring(), value: showToast)
        }
        .frame(minWidth: 1220, minHeight: 700)
        .onAppear { locationManager.requestPermission(); updateStatus() }
        .onReceive(timer) { _ in
            if isAutoScanEnabled && !isScanning { scanWifi(clear: false) }
            updateStatus()
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wi-Fi Scanner").font(.title).bold()
                HStack(spacing: 12) {
                    Text("Showing: \(filteredNetworks.count) / Total: \(allNetworks.count)")
                    if let ssid = currentSSID {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                            Text("Connected: \(ssid)").bold().foregroundColor(.blue)
                        }
                    }
                    if !lastUpdateTime.isEmpty { Text("(Last: \(lastUpdateTime))").foregroundColor(.secondary) }
                }
                .font(.body).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: exportCSV) { Label("Export CSV", systemImage: "square.and.arrow.up") }
            Toggle("Auto Scan(3s)", isOn: $isAutoScanEnabled).toggleStyle(.checkbox).padding(.horizontal)
            Button(action: { scanWifi(clear: true) }) { Label(isScanning ? "..." : "Manual Scan", systemImage: "antenna.radiowaves.left.and.right") }.disabled(isScanning)
        }.padding()
    }

    private var filterPanel: some View {
        HStack(spacing: 15) {
            Picker("", selection: $selectedBand) { ForEach(BandFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).frame(width: 200)

            Picker("Sec", selection: $selectedSecurity) { ForEach(SecurityFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 185)
            Picker("RSSI", selection: $selectedRSSI) { ForEach(RSSIFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 175)
            TextField("Search SSID or BSSID...", text: $searchText).textFieldStyle(.roundedBorder).font(.body).frame(maxWidth: .infinity)
        }.padding(.horizontal).padding(.bottom, 12)
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            sortButton("SSID", key: .ssid, width: 200)
            sortButton("Standard", key: .standard, width: 125)
            sortButton("BSSID", key: .bssid, width: 180)
            Text("Mode").frame(width: 100, alignment: .leading)
            sortButton("Band", key: .band, width: 70)
            sortButton("Width", key: .width, width: 75, alignment: .center)
            sortButton("CH", key: .channel, width: 50, alignment: .center)
            Text("Security").frame(width: 150, alignment: .leading)
            Spacer(minLength: 10)
            sortButton("Signal", key: .rssi, width: 95, alignment: .trailing)
        }
        .font(.system(size: 13, weight: .bold)).padding(.horizontal, 20).padding(.vertical, 10).background(Color(NSColor.windowBackgroundColor))
    }

    private func handleSelectionToggle(for bssid: String, isCommandPressed: Bool) {
        if isCommandPressed {
            if selection.contains(bssid) { selection.remove(bssid) } else { selection.insert(bssid) }
        } else {
            if selection.count == 1 && selection.contains(bssid) {
                selection.removeAll()
            } else {
                selection = [bssid]
            }
        }
    }

    func triggerToast(message: String) {
        toastMessage = message
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showToast = false }
        }
    }

    func copySelectedItemsAsCSV() {
        let selectedItems = filteredNetworks.filter { selection.contains($0.bssid) }
        guard !selectedItems.isEmpty else { return }
        let header = "SSID,Standard,BSSID,Band,Width,CH,Security,RSSI"
        let rows = selectedItems.map {
            let safeSSID = $0.ssid.replacingOccurrences(of: ",", with: "")
            return "\(safeSSID),\($0.standard),\($0.bssid),\($0.bandString),\($0.channelWidthString),\($0.channel),\($0.security) \($0.authType),\($0.rssi)dBm"
        }.joined(separator: "\n")
        copyToClipboard(header + "\n" + rows)
    }

    func updateStatus() {
        if let interface = CWWiFiClient.shared().interface() {
            self.currentSSID = interface.ssid()
        }
    }

    func scanWifi(clear: Bool) {
        self.isScanning = true; if clear { self.allNetworks = [] }
        DispatchQueue.global(qos: .userInitiated).async {
            let found = (try? CWWiFiClient.shared().interface()?.scanForNetworks(withSSID: nil)) ?? []
            var unique: [String: CWNetwork] = [:]
            for net in found { if let b = net.bssid { unique[b] = net } }
            let results = unique.values.map { WifiNetwork(raw: $0) }
            let timeString = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            DispatchQueue.main.async {
                self.allNetworks = results; self.lastUpdateTime = timeString
                self.applySort(); self.isScanning = false
            }
        }
    }

    func applySort() {
        allNetworks.sort { (a, b) -> Bool in
            let r: Bool
            switch sortKey {
                case .ssid: r = a.ssid < b.ssid
                case .standard: r = a.standard < b.standard
                case .bssid: r = a.bssid < b.bssid
                case .band: r = a.bandValue < b.bandValue
                case .width: r = a.channelWidthString < b.channelWidthString
                case .rssi: r = a.rssi < b.rssi
                case .channel: r = a.channel < b.channel
            }
            return isAscending ? r : !r
        }
    }

    func sortButton(_ title: String, key: SortKey, width: CGFloat, alignment: Alignment = .leading) -> some View {
        Button(action: { if sortKey == key { isAscending.toggle() } else { sortKey = key; isAscending = false }; applySort() }) {
            HStack(spacing: 4) {
                Text(title)
                if sortKey == key {
                    Image(systemName: isAscending ? "chevron.up" : "chevron.down").font(.system(size: 9))
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: width, alignment: alignment)
    }

    func exportCSV() {
        let bom = "\u{FEFF}"; let now = Date(); let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"; let ts = f.string(from: now)
        let rows = filteredNetworks.map { "\(ts),\($0.ssid.replacingOccurrences(of: ",", with: "")),\($0.standard),\($0.bssid),\($0.mode),\($0.bandString),\($0.channelWidthString),\($0.channel),\($0.security) \($0.authType),\($0.rssi)" }.joined(separator: "\n")
        let csv = bom + "Timestamp,SSID,Standard,BSSID,Mode,Band,Width,Channel,Security_Auth,RSSI\n" + rows
        f.dateFormat = "yyyyMMdd_HHmmss"
        DispatchQueue.main.async {
            let sp = NSSavePanel(); sp.allowedContentTypes = [.commaSeparatedText]; sp.nameFieldStringValue = "wifi_audit_\(f.string(from: now)).csv"
            sp.begin { response in if response == .OK, let url = sp.url { try? csv.write(to: url, atomically: true, encoding: .utf8) } }
        }
    }

    func copyToClipboard(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}
