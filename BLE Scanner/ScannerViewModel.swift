import Foundation
import CoreBluetooth

@MainActor
class ScannerViewModel: NSObject, ObservableObject, CBCentralManagerDelegate {
    
    // --- Published properties ---
    @Published var matchedTags: [DiscoveredTag] = []
    @Published var allDiscoveredDevices: [GenericDevice] = []
    @Published var statusMessage: String = "Initializing..."
    @Published var anchorId: String = ""
    @Published var scanProgress: Double = 0.0
    @Published var isJobScanning: Bool = false
    @Published var isDebugScanning: Bool = false
    
    // --- Private properties ---
    private var centralManager: CBCentralManager!
    private let networkService = NetworkService()
    
    private var jobPollingTimer: Timer?
    private let jobPollingInterval: TimeInterval = 3.0
    
    private var scanTimer: Timer?
    private var progressTimer: Timer?
    
    // --- State for the current job ---
    private var currentJob: ScanJob?
    private var tagsForCurrentJob: [String: EventTag] = [:] // Maps UUID to EventTag object
    private var minRSSIForJob: Int = -100
    
    // --- Eddystone Specific Constants ---
    private let eddystoneServiceUUID = CBUUID(string: "FEAA")
    private let expectedNamespace = "76656C6176752E636F6D"

    override init() {
        super.init()
        setupAnchorId()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    private func setupAnchorId() {
        let defaults = UserDefaults.standard
        let anchorIdKey = "anchorId"
        
        var needsUpdateOrCreation = false
        if let savedId = defaults.string(forKey: anchorIdKey) {
            if savedId.contains("-") || savedId.count != 12 {
                needsUpdateOrCreation = true
                print("Old Anchor ID format detected. A new one will be generated.")
            } else {
                self.anchorId = savedId
                print("Loaded existing Anchor ID: \(savedId)")
            }
        } else {
            needsUpdateOrCreation = true
        }
        
        if needsUpdateOrCreation {
            let newId = String(UUID().uuidString.split(separator: "-").last ?? "errorid").lowercased()
            self.anchorId = newId
            defaults.set(newId, forKey: anchorIdKey)
            print("Generated and saved new Anchor ID: \(newId)")
        }
    }
    
    // --- Core Logic ---
    private func startPollingForJobs() {
        jobPollingTimer?.invalidate()
        statusMessage = "Idle. Polling for new job..."
        jobPollingTimer = Timer.scheduledTimer(withTimeInterval: jobPollingInterval, repeats: true) { [weak self] _ in
            guard let self = self, !self.isJobScanning, !self.isDebugScanning else { return }
            Task { await self.checkForNewJob() }
        }
        jobPollingTimer?.fire()
    }
    
    private func checkForNewJob() async {
        guard !anchorId.isEmpty else {
            statusMessage = "Waiting for Anchor ID..."
            return
        }
        
        do {
            if let job = try await networkService.fetchJob(for: anchorId) {
                jobPollingTimer?.invalidate()
                await executeJob(job)
            } else {
                statusMessage = "Idle. No job found. Polling..."
            }
        } catch {
            statusMessage = "Error checking for job. Retrying..."
            print("Job fetch failed: \(error.localizedDescription)")
        }
    }
    
    private func executeJob(_ job: ScanJob) async {
        print("\n>>> EXECUTING NEW JOB: \(job.scan_id) <<<")
        self.currentJob = job
        
        if let rssiValue = Int(job.scan_min_rssi), rssiValue < 0 {
            self.minRSSIForJob = rssiValue
        } else {
            print("Warning: Invalid 'scan_min_rssi' value (\(job.scan_min_rssi)). Defaulting to -100.")
            self.minRSSIForJob = -100
        }
        
        let actualScanDuration = calculateScanDuration(for: job)
        
        if actualScanDuration <= 0 {
            print("Job \(job.scan_id) has already expired. Ignoring and restarting poll.")
            cleanUpAndRestartPolling()
            return
        }
        
        statusMessage = "Received Job \(job.scan_id). Fetching tags..."
        do {
            let eventTags = try await networkService.fetchTags(for: job.event_id)
            self.tagsForCurrentJob = Dictionary(uniqueKeysWithValues: eventTags.map { ($0.uuid.uppercased(), $0) })
            startScanning(duration: actualScanDuration)
        } catch {
            statusMessage = "Failed to prepare job \(job.scan_id). Retrying..."
            print("Failed to execute job: \(error.localizedDescription)")
            cleanUpAndRestartPolling()
        }
    }
    
    private func calculateScanDuration(for job: ScanJob) -> TimeInterval {
        let jobDuration = TimeInterval(job.scan_duration) ?? 120.0
        let jobTimeout = TimeInterval(job.scan_timeout ?? "120.0") ?? 120.0
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        guard let creationDate = dateFormatter.date(from: job.cct_created),
              let serverDate = dateFormatter.date(from: job.server_time) else {
            print("Warning: Could not parse job/server dates. Using job duration as fallback.")
            return jobDuration
        }
        
        let expiryDate = creationDate.addingTimeInterval(jobTimeout)
        let timeUntilExpiry = serverDate.distance(to: expiryDate)
        
        let effectiveDuration = min(jobDuration, timeUntilExpiry - 5.0)
        
        print("Job Duration: \(jobDuration)s, Time Until Expiry: \(timeUntilExpiry)s. Effective Scan Duration: \(effectiveDuration)s")
        
        return max(0, effectiveDuration)
    }
    
    private func startScanning(duration: TimeInterval) {
        guard centralManager.state == .poweredOn else {
            statusMessage = "Bluetooth is not available."
            cleanUpAndRestartPolling()
            return
        }
        
        isJobScanning = true
        statusMessage = "Scanning for \(duration.rounded())s (Job: \(currentJob?.scan_id ?? ""))..."
        
        matchedTags.removeAll()
        allDiscoveredDevices.removeAll()
        
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        
        scanProgress = 0.0
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.scanProgress += 1.0 / duration
            if self.scanProgress >= 1.0 {
                self.progressTimer?.invalidate()
            }
        }
        
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { await self?.finishJobAndUploadResults() }
        }
    }
    
    private func finishJobAndUploadResults() async {
        guard isJobScanning else { return }
        
        centralManager.stopScan()
        scanTimer?.invalidate()
        progressTimer?.invalidate()
        isJobScanning = false
        scanProgress = 0.0
        
        guard let job = currentJob else {
            print("Error: finishJobAndUploadResults called without a current job. Restarting polling.")
            cleanUpAndRestartPolling()
            return
        }
        
        print("\n>>> FINISHING JOB: \(job.scan_id) <<<")
        statusMessage = "Scan complete. Uploading \(matchedTags.count) results..."
        
        do {
            let payload = matchedTags.map {
                ScanDataPayload(scan_id: job.scan_id,
                                scan_data_tag_id: $0.db_id,
                                scan_data_tag_rssi: $0.rssi,
                                scan_data_anchor_id: job.anchor_db_id)
            }
            
            if !payload.isEmpty {
                try await networkService.uploadScanData(payload: payload)
            } else {
                print("No matching tags found to upload.")
            }
            
            let relationPayload = JobAnchorRelationPayload(parent_id: job.scan_id, child_id: job.anchor_db_id)
            try await networkService.updateJobAnchorRelationship(payload: relationPayload)
            
            statusMessage = "Upload complete for job \(job.scan_id)."
            
        } catch {
            statusMessage = "Upload failed for job \(job.scan_id)."
            print("Upload failed: \(error.localizedDescription)")
        }
        
        cleanUpAndRestartPolling()
    }
    
    private func cleanUpAndRestartPolling() {
        self.currentJob = nil
        self.tagsForCurrentJob.removeAll()
        self.matchedTags.removeAll()
        startPollingForJobs()
    }
    
    func startDebugScan() {
        guard !isJobScanning && !isDebugScanning else { return }

        isDebugScanning = true
        statusMessage = "Starting 15s debug scan..."
        allDiscoveredDevices.removeAll()

        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])

        Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            self?.stopDebugScan()
        }
    }

    private func stopDebugScan() {
        guard isDebugScanning else { return }
        centralManager.stopScan()
        isDebugScanning = false
    }

    // --- CBCentralManagerDelegate Methods ---
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            statusMessage = "Bluetooth is ON."
            startPollingForJobs()
        } else {
            statusMessage = "Bluetooth is not available. Please turn it on."
            isJobScanning = false
            jobPollingTimer?.invalidate()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let rssiValue = RSSI.intValue
        
        if isJobScanning && rssiValue < minRSSIForJob {
            return
        }
        
        var details = "N/A"
        var eddystoneInstanceId: String? = nil
        
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
           let eddystoneData = serviceData[eddystoneServiceUUID] {
            
            let eddystoneHexString = eddystoneData.hexEncodedString().uppercased()
            details = "Eddystone Service: \(eddystoneHexString)"

            updateDebugView(peripheral: peripheral, rssi: rssiValue, advertisementDetails: details)

            if let frameType = eddystoneData.first, frameType == 0x00, eddystoneData.count >= 18 {
                let namespaceData = eddystoneData.subdata(in: 2..<12)
                let namespaceString = namespaceData.hexEncodedString().uppercased()
                if namespaceString == expectedNamespace.uppercased() {
                    let instanceData = eddystoneData.subdata(in: 12..<18)
                    eddystoneInstanceId = instanceData.hexEncodedString().uppercased()
                }
            }
        }
        else if !isDebugScanning {
            details = "Manuf. Data: \((advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?.hexEncodedString().uppercased() ?? "N/A")"
            updateDebugView(peripheral: peripheral, rssi: rssiValue, advertisementDetails: details)
        }
        
        if isJobScanning, let instanceString = eddystoneInstanceId {
            matchInstanceIdToJobTags(instanceString: instanceString, rssi: rssiValue)
        }
    }
    
    private func matchInstanceIdToJobTags(instanceString: String, rssi rssiValue: Int) {
        for (apiUUID, eventTag) in tagsForCurrentJob {
            if apiUUID.hasSuffix(String(instanceString.suffix(6))) {
                
                let isNewDiscovery = !matchedTags.contains(where: { $0.id == eventTag.velavu_id })
                
                if isNewDiscovery {
                    let newTag = DiscoveredTag(id: eventTag.velavu_id, uuid: eventTag.uuid, db_id: eventTag.db_id, rssi: rssiValue, lastSeen: Date())
                    matchedTags.append(newTag)
                } else if let index = matchedTags.firstIndex(where: { $0.id == eventTag.velavu_id }) {
                    if rssiValue > matchedTags[index].rssi {
                        matchedTags[index].rssi = rssiValue
                        matchedTags[index].lastSeen = Date()
                    }
                }
                
                matchedTags.sort { $0.rssi > $1.rssi }
                
                if isNewDiscovery && matchedTags.count == tagsForCurrentJob.count && !tagsForCurrentJob.isEmpty {
                    print(">>> All \(tagsForCurrentJob.count) job tags found! Finishing scan early. <<<")
                    Task { await finishJobAndUploadResults() }
                }
                
                break
            }
        }
    }

    private func updateDebugView(peripheral: CBPeripheral, rssi: Int, advertisementDetails: String) {
        let now = Date()
        if let index = allDiscoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            allDiscoveredDevices[index].rssi = rssi
            allDiscoveredDevices[index].advertisementDetails = advertisementDetails
            allDiscoveredDevices[index].lastSeen = now
        } else {
            let newDevice = GenericDevice(id: peripheral.identifier, name: peripheral.name ?? "Unknown Device", rssi: rssi, advertisementDetails: advertisementDetails, lastSeen: now)
            allDiscoveredDevices.append(newDevice)
        }
        allDiscoveredDevices.sort { $0.rssi > $1.rssi }
    }
}

// Helper extension to convert Data to a hex string.
extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
