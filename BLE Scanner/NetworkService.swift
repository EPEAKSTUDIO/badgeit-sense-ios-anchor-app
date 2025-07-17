import Foundation

class NetworkService {
    // The token is now accessed from the secure, untracked APIKeys file.
    private let bearerToken = APIKeys.bearerToken
    
    // --- Endpoint to fetch a new job for this anchor ---
    func fetchJob(for anchorId: String) async throws -> ScanJob? {
        let urlString = "https://app.badgeit.io/wp-json/badgeit/scan-by-anchor/?anchor_id=\(anchorId)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        
        print("\n--- POLLING FOR JOB ---")
        print("URL: \(url.absoluteString)")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let responseString = String(data: data, encoding: .utf8) {
            print("--- JOB RESPONSE PAYLOAD ---\n\(responseString)\n--------------------------")
        }
        
        let jobs = try JSONDecoder().decode([ScanJob].self, from: data)
        return jobs.first
    }
    
    // --- Endpoint to get tags for a specific event ---
    func fetchTags(for eventId: String) async throws -> [EventTag] {
        let urlString = "https://app.badgeit.io/wp-json/badgeit/get-tags-by-event/?event_id=\(eventId)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        
        print("\n--- FETCHING TAGS FOR EVENT \(eventId) ---")
        print("URL: \(url.absoluteString)")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let responseString = String(data: data, encoding: .utf8) {
            print("--- TAGS RESPONSE PAYLOAD ---\n\(responseString)\n---------------------------")
        }
        
        return try JSONDecoder().decode([EventTag].self, from: data)
    }
    
    // --- Endpoint to upload batch scan data ---
    func uploadScanData(payload: [ScanDataPayload]) async throws {
        let url = URL(string: "https://app.badgeit.io/wp-json/jetenginecctbulk/v1/scan_data")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        
        let jsonData = try JSONEncoder().encode(payload)
        request.httpBody = jsonData
        
        print("\n--- UPLOADING SCAN DATA ---")
        print("URL: \(url.absoluteString)")
        if let bodyString = String(data: jsonData, encoding: .utf8) {
            print("--- UPLOAD PAYLOAD ---\n\(bodyString)\n----------------------")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("--- UPLOAD RESPONSE ---")
            print("Status Code: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("Response Body: \(responseString)")
            }
            print("-----------------------")
        }
    }
    
    // --- Endpoint to update the relationship ---
    func updateJobAnchorRelationship(payload: JobAnchorRelationPayload) async throws {
        let url = URL(string: "https://app.badgeit.io/wp-json/jet-rel/230")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        
        let jsonData = try JSONEncoder().encode(payload)
        request.httpBody = jsonData
        
        print("\n--- UPDATING JOB RELATIONSHIP ---")
        print("URL: \(url.absoluteString)")
        if let bodyString = String(data: jsonData, encoding: .utf8) {
            print("--- RELATIONSHIP PAYLOAD ---\n\(bodyString)\n----------------------------")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("--- RELATIONSHIP RESPONSE ---")
            print("Status Code: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("Response Body: \(responseString)")
            }
            print("-----------------------------")
        }
    }
}
