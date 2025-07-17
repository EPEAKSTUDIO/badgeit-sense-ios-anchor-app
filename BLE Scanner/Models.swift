import Foundation

// MARK: - API Data Models

// --- Models for fetching jobs ---
struct ScanJob: Codable {
    let scan_id: String
    let anchor_velavu_id: String
    let scan_duration: String
    let scan_min_rssi: String
    let scan_timeout: String?
    let cct_created: String
    let event_id: String
    let anchor_db_id: String
    let server_time: String

    enum CodingKeys: String, CodingKey {
        case scan_id = "jet_cct_scan._ID"
        case anchor_velavu_id = "jet_cct_anchorscct.anchor_velavu_id"
        case scan_duration = "jet_cct_scan.scan_duration"
        case scan_min_rssi = "jet_cct_scan.scan_min_rssi"
        case scan_timeout = "jet_cct_scan.scan_timeout"
        case cct_created = "jet_cct_scan.cct_created"
        case event_id = "jet_rel_228.parent_object_id"
        case anchor_db_id = "jet_cct_anchorscct._ID"
        case server_time
    }
}

// --- Models for fetching tags for a specific event ---
struct EventTag: Codable {
    let db_id: String
    let uuid: String
    let velavu_id: String

    enum CodingKeys: String, CodingKey {
        case db_id = "jet_cct_tagscct._ID"
        case uuid = "jet_cct_tagscct.tag_uuid"
        case velavu_id = "jet_cct_tagscct.tag_velavu_id"
    }
}

// --- Models for uploading scan results ---
struct ScanDataPayload: Codable {
    let scan_id: String
    let scan_data_tag_id: String
    let scan_data_tag_rssi: Int
    let scan_data_anchor_id: String
}

// --- Models for updating the job-anchor relationship ---
struct JobAnchorRelationPayload: Codable {
    let parent_id: String
    let child_id: String
    let context: String = "parent"
    let store_items_type: String = "update"
}


// MARK: - UI & Internal State Data Models

struct DiscoveredTag: Identifiable, Hashable {
    let id: String // velavu_id
    let uuid: String // tag_uuid
    let db_id: String // tag's database ID for upload
    var rssi: Int
    var lastSeen: Date
    
    var lastSeenFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: lastSeen)
    }
}

struct GenericDevice: Identifiable, Hashable {
    let id: UUID
    let name: String
    var rssi: Int
    var advertisementDetails: String
    var lastSeen: Date
    
    var lastSeenFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: lastSeen)
    }
}
