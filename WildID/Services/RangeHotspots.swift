import CoreLocation
import Foundation
import MapKit
import UIKit

/// A place where a species is recorded a lot: drawn as a soft circle, red at the busiest point
/// fading to yellow and then transparent at the edge (stronger = more records).
struct RangeHotspot: Equatable, Identifiable {
    let center: CLLocationCoordinate2D
    let radiusMeters: CLLocationDistance
    /// 0…1 relative to the busiest hotspot in view.
    let weight: Double
    var id: String { "\(center.latitude),\(center.longitude),\(radiusMeters)" }
    static func == (a: RangeHotspot, b: RangeHotspot) -> Bool { a.id == b.id && a.weight == b.weight }
}

/// Builds hotspots from iNaturalist's observation grid (UTFGrid JSON tiles: a 64×64 character
/// grid per map tile where every non-blank character is a cell with research-grade records).
enum RangeHotspots {
    struct GridTile: Decodable {
        let grid: [String]
        let keys: [String]
        let data: [String: Cell]?
        struct Cell: Decodable {
            let cellCount: Int?
            let count: Int?
            var value: Int { cellCount ?? count ?? 1 }
        }
    }

    struct Cell { let coordinate: CLLocationCoordinate2D; let count: Int }

    /// UTFGrid character → key index (the standard encoding).
    static func keyIndex(_ scalar: Unicode.Scalar) -> Int {
        var code = Int(scalar.value)
        if code >= 93 { code -= 1 }
        if code >= 35 { code -= 1 }
        return code - 32
    }

    /// Centre coordinate of grid cell (col,row) of tile (x,y,z).
    static func coordinate(z: Int, x: Int, y: Int, col: Int, row: Int, size: Int) -> CLLocationCoordinate2D {
        let n = pow(2.0, Double(z))
        let fx = (Double(x) + (Double(col) + 0.5) / Double(size)) / n
        let fy = (Double(y) + (Double(row) + 0.5) / Double(size)) / n
        let lon = fx * 360 - 180
        let lat = atan(sinh(Double.pi * (1 - 2 * fy))) * 180 / Double.pi
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Cells of one tile.
    static func cells(of tile: GridTile, z: Int, x: Int, y: Int) -> [Cell] {
        var out: [Cell] = []
        let size = tile.grid.count
        for (row, line) in tile.grid.enumerated() {
            for (col, scalar) in line.unicodeScalars.enumerated() where scalar != " " {
                let i = keyIndex(scalar)
                guard i > 0, i < tile.keys.count else { continue }      // index 0 = empty
                let count = tile.data?[tile.keys[i]]?.value ?? 1
                out.append(Cell(coordinate: coordinate(z: z, x: x, y: y, col: col, row: row, size: size), count: count))
            }
        }
        return out
    }

    /// Greedy clustering: the busiest cells seed hotspots; cells within `mergeKm` join the nearest.
    /// Keeps the `limit` strongest hotspots. Pure function (unit-tested).
    static func cluster(_ cells: [Cell], mergeKm: Double, limit: Int = 8) -> [RangeHotspot] {
        struct Acc { var lat = 0.0, lon = 0.0, total = 0.0, maxDist = 0.0; var seed: CLLocation; var members: [Cell] = [] }
        var groups: [Acc] = []
        for cell in cells.sorted(by: { $0.count > $1.count }) {
            let loc = CLLocation(latitude: cell.coordinate.latitude, longitude: cell.coordinate.longitude)
            if let i = groups.indices.min(by: { groups[$0].seed.distance(from: loc) < groups[$1].seed.distance(from: loc) }),
               groups[i].seed.distance(from: loc) <= mergeKm * 1000 {
                groups[i].members.append(cell)
            } else {
                groups.append(Acc(seed: loc, members: [cell]))
            }
        }
        var spots: [(CLLocationCoordinate2D, Double, Double)] = []
        for g in groups {
            let total = g.members.reduce(0.0) { $0 + Double($1.count) }
            let lat = g.members.reduce(0.0) { $0 + $1.coordinate.latitude * Double($1.count) } / total
            let lon = g.members.reduce(0.0) { $0 + $1.coordinate.longitude * Double($1.count) } / total
            let c = CLLocation(latitude: lat, longitude: lon)
            let spread = g.members.map { c.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)) }.max() ?? 0
            spots.append((CLLocationCoordinate2D(latitude: lat, longitude: lon), max(spread * 1.25, mergeKm * 350), total))
        }
        let top = spots.sorted { $0.2 > $1.2 }.prefix(limit)
        let maxTotal = top.first?.2 ?? 1
        return top.map { RangeHotspot(center: $0.0, radiusMeters: $0.1, weight: sqrt($0.2 / maxTotal)) }
    }

    /// Hotspots for a species in the visible region: picks a zoom where the region covers a few
    /// tiles, fetches them (cached) and clusters at about 1/8 of the view's width.
    static func load(taxonID: Int, region: MKCoordinateRegion) async -> [RangeHotspot] {
        let lonSpan = max(0.5, min(360, region.span.longitudeDelta))
        let z = max(1, min(10, Int(log2(360 / lonSpan)) + 1))
        let n = Int(pow(2.0, Double(z)))
        func tileX(_ lon: Double) -> Int { max(0, min(n - 1, Int((lon + 180) / 360 * Double(n)))) }
        func tileY(_ lat: Double) -> Int {
            let r = max(-85, min(85, lat)) * Double.pi / 180
            return max(0, min(n - 1, Int((1 - log(tan(r) + 1 / cos(r)) / Double.pi) / 2 * Double(n))))
        }
        let minLat = region.center.latitude - region.span.latitudeDelta / 2, maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - lonSpan / 2, maxLon = region.center.longitude + lonSpan / 2
        let xs = lonSpan >= 359 ? Array(0..<n) : Array(Set([tileX(minLon), tileX(region.center.longitude), tileX(maxLon)])).sorted()
        let ys = Array(tileY(maxLat)...tileY(minLat))
        let coords = xs.flatMap { x in ys.map { (x, $0) } }.prefix(24)
        var all: [Cell] = []
        await withTaskGroup(of: [Cell].self) { group in
            for (x, y) in coords {
                group.addTask {
                    guard let url = URL(string: "\(INaturalistAPI.base)/grid/\(z)/\(x)/\(y).grid.json?taxon_id=\(taxonID)&quality_grade=research"),
                          let tile = try? await HTTPClient.shared.get(GridTile.self, from: url, maxAge: 60 * 60 * 24 * 7) else { return [] }
                    return cells(of: tile, z: z, x: x, y: y)
                }
            }
            for await c in group { all += c }
        }
        let widthKm = lonSpan * 111 * cos(region.center.latitude * Double.pi / 180)
        return cluster(all, mergeKm: max(25, widthKm / 8))
    }
}

/// MapKit overlay for a hotspot (an `MKCircle` carrying its weight).
final class HotspotOverlay: MKCircle {
    var weight: Double = 1
    convenience init(_ spot: RangeHotspot) {
        self.init(center: spot.center, radius: spot.radiusMeters)
        weight = spot.weight
    }
}

/// Draws a radial gradient: red at the centre, orange, then yellow fading to transparent.
final class HotspotRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let circle = overlay as? HotspotOverlay else { return }
        let rect = self.rect(for: circle.boundingMapRect)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2
        let a = CGFloat(0.35 + 0.4 * circle.weight)
        let colors = [UIColor(red: 0.86, green: 0.12, blue: 0.10, alpha: a).cgColor,
                      UIColor(red: 0.97, green: 0.47, blue: 0.12, alpha: a * 0.8).cgColor,
                      UIColor(red: 1.00, green: 0.82, blue: 0.20, alpha: a * 0.55).cgColor,
                      UIColor(red: 1.00, green: 0.90, blue: 0.35, alpha: 0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 0.75, 1]) else { return }
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        // A thin outline marks the edge of the area.
        context.setStrokeColor(UIColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 0.55).cgColor)
        context.setLineWidth(1.5 / zoomScale)
        context.strokeEllipse(in: rect.insetBy(dx: 1 / zoomScale, dy: 1 / zoomScale))
    }
}
