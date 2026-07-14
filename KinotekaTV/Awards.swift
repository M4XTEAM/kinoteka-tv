import SwiftUI

// ===========================================================
// Награды и номинации из Wikidata (SPARQL) — как в PWA:
// для тайтла (кто получил ЗА эту работу + награды самого тайтла)
// и для персоны (что получила/номинирована).
// ===========================================================

struct AwardRow: Identifiable, Hashable {
    let id = UUID()
    let awardLabel: String
    let year: String
    let won: Bool
    let detail: String   // тайтл: за кого (personLabel); персона: за что (workLabel)
}

enum Wikidata {
    private enum Mode { case title, person }

    // Кэш по ключу режим/qid, чтобы не дёргать Wikidata повторно.
    private static var cache: [String: [AwardRow]] = [:]

    static func titleAwards(_ wd: String) async -> [AwardRow] { await run(wd, mode: .title) }
    static func personAwards(_ wd: String) async -> [AwardRow] { await run(wd, mode: .person) }

    private static func run(_ wd: String, mode: Mode) async -> [AwardRow] {
        guard wd.hasPrefix("Q") else { return [] }
        let key = "\(mode)/\(wd)"
        if let c = cache[key] { return c }

        let q: String
        if mode == .title {
            q = """
            SELECT ?award ?awardLabel ?date ?person ?personLabel ?status WHERE {
              { ?person p:P166 ?st. ?st ps:P166 ?award. ?st pq:P1686 wd:\(wd). BIND("won" AS ?status) }
              UNION
              { ?person p:P1411 ?st. ?st ps:P1411 ?award. ?st pq:P1686 wd:\(wd). BIND("nominated" AS ?status) }
              UNION
              { wd:\(wd) p:P166 ?st. ?st ps:P166 ?award. BIND("won" AS ?status) }
              UNION
              { wd:\(wd) p:P1411 ?st. ?st ps:P1411 ?award. BIND("nominated" AS ?status) }
              OPTIONAL { ?st pq:P585 ?date. }
              SERVICE wikibase:label { bd:serviceParam wikibase:language "ru,en". }
            } ORDER BY DESC(?date)
            """
        } else {
            q = """
            SELECT ?award ?awardLabel ?date ?work ?workLabel ?status WHERE {
              { wd:\(wd) p:P166 ?st. ?st ps:P166 ?award. BIND("won" AS ?status) }
              UNION
              { wd:\(wd) p:P1411 ?st. ?st ps:P1411 ?award. BIND("nominated" AS ?status) }
              OPTIONAL { ?st pq:P585 ?date. }
              OPTIONAL { ?st pq:P1686 ?work. }
              SERVICE wikibase:label { bd:serviceParam wikibase:language "ru,en". }
            } ORDER BY DESC(?date)
            """
        }

        let bindings = (try? await sparql(q)) ?? []
        let result = parse(bindings, detailKey: mode == .title ? "personLabel" : "workLabel")
        cache[key] = result
        return result
    }

    // ---- Сеть ----
    private static func sparql(_ query: String) async throws -> [[String: String]] {
        var comp = URLComponents(string: "https://query.wikidata.org/sparql")!
        comp.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "query", value: query),
        ]
        guard let url = comp.url else { return [] }
        var req = URLRequest(url: url)
        req.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        req.setValue("KinotekaTV/1.0 (https://kinoteka.pages.dev)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let results = obj?["results"] as? [String: Any]
        let bindings = results?["bindings"] as? [[String: Any]] ?? []
        return bindings.map { b in
            var row: [String: String] = [:]
            for (k, v) in b {
                if let cell = v as? [String: Any], let value = cell["value"] as? String {
                    row[k] = value
                }
            }
            return row
        }
    }

    // ---- Разбор + дедуп (упрощённо, как в PWA) ----
    private static func isQid(_ s: String) -> Bool {
        s.first == "Q" && s.dropFirst().allSatisfy(\.isNumber)
    }

    private static func parse(_ rows: [[String: String]], detailKey: String) -> [AwardRow] {
        struct Raw { let label: String; let year: String; let won: Bool; let detail: String }
        let raws: [Raw] = rows.compactMap { r in
            guard let label = r["awardLabel"], !label.isEmpty, !isQid(label) else { return nil }
            let year = (r["date"].map { String($0.prefix(4)) }) ?? ""
            let won = r["status"] == "won"
            var detail = r[detailKey] ?? ""
            if isQid(detail) { detail = "" }
            return Raw(label: label, year: year, won: won, detail: detail)
        }
        // Если за одну работу/год и победа, и номинация — оставляем победу.
        let wonKeys = Set(raws.filter(\.won).map { "\($0.label)|\($0.year)|\($0.detail)" })
        var seen = Set<String>()
        var out: [AwardRow] = []
        for r in raws {
            let base = "\(r.label)|\(r.year)|\(r.detail)"
            if !r.won && wonKeys.contains(base) { continue }
            let k = base + "|\(r.won)"
            if seen.contains(k) { continue }
            seen.insert(k)
            out.append(AwardRow(awardLabel: r.label, year: r.year, won: r.won, detail: r.detail))
        }
        // Победы вперёд, затем по году убыв.
        return out.sorted { ($0.won ? 1 : 0, $0.year) > ($1.won ? 1 : 0, $1.year) }
    }
}

// ---- Секция наград ----
struct AwardsSection: View {
    let awards: [AwardRow]
    @State private var expanded = false

    var body: some View {
        if !awards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Награды и номинации")
                VStack(spacing: 8) {
                    ForEach(expanded ? awards : Array(awards.prefix(3))) { a in
                        HStack(spacing: 12) {
                            Image(systemName: a.won ? "trophy.fill" : "rosette")
                                .font(.body)
                                .foregroundStyle(a.won ? Theme.accent : .secondary)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.awardLabel)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(2)
                                Text([a.year, a.won ? "Победа" : "Номинация", a.detail]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 20)

                if awards.count > 3 {
                    Button(expanded ? "Свернуть" : "Показать все (\(awards.count))") {
                        withAnimation { expanded.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 24)
        }
    }
}
