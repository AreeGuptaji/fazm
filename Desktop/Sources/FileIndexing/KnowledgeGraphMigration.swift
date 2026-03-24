import Foundation

/// One-time migration of existing KG data to Hindsight
enum KnowledgeGraphMigration {
    private static let kMigratedFlag = "kg_migrated_to_hindsight"

    /// Run the migration if not already done. Waits for Hindsight to be healthy, then retains KG data.
    /// Call from app startup (e.g., AppDelegate) with a delay to give Hindsight time to start.
    static func migrateIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: kMigratedFlag) else {
            log("KGMigration: already migrated, skipping")
            return
        }

        // Wait for Hindsight to be healthy (poll up to 5 times, every 10s)
        let healthy = await waitForHindsight(maxRetries: 5, interval: 10)
        guard healthy else {
            log("KGMigration: Hindsight not ready after retries, will try next launch")
            return
        }

        // Load existing KG data
        let (nodes, edges) = await KnowledgeGraphStorage.shared.loadRawRecords()
        if nodes.isEmpty {
            log("KGMigration: no KG data to migrate, setting flag")
            UserDefaults.standard.set(true, forKey: kMigratedFlag)
            return
        }

        log("KGMigration: migrating \(nodes.count) nodes, \(edges.count) edges to Hindsight")

        // Retain to Hindsight using shared helper
        let text = ChatToolExecutor.formatKGAsText(nodes: nodes, edges: edges)
        guard !text.isEmpty else {
            UserDefaults.standard.set(true, forKey: kMigratedFlag)
            return
        }

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": [
                "name": "retain",
                "arguments": [
                    "content": text,
                    "context": "onboarding_knowledge_graph_migration",
                    "tags": ["onboarding", "knowledge_graph", "migration"]
                ]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            log("KGMigration: failed to serialize JSON")
            return
        }

        guard let url = URL(string: "http://127.0.0.1:18888/mcp/default/") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode >= 200 && statusCode < 300 {
                log("KGMigration: success — migrated \(nodes.count) nodes, \(edges.count) edges")
                UserDefaults.standard.set(true, forKey: kMigratedFlag)
            } else {
                let body = String(data: data, encoding: .utf8) ?? ""
                log("KGMigration: HTTP \(statusCode): \(body.prefix(200))")
            }
        } catch {
            log("KGMigration: \(error.localizedDescription) — will retry next launch")
        }
    }

    /// Poll Hindsight health endpoint
    private static func waitForHindsight(maxRetries: Int, interval: TimeInterval) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:18888/health") else { return false }

        for attempt in 1...maxRetries {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5
                let (_, response) = try await URLSession.shared.data(for: request)
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    log("KGMigration: Hindsight healthy (attempt \(attempt))")
                    return true
                }
            } catch {
                // expected — Hindsight may not be up yet
            }

            if attempt < maxRetries {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
        return false
    }
}
