import XCTest
@testable import WildID

/// Decodes real API payload shapes (captured from the live APIs) into WildID's models.
final class DecodingTests: XCTestCase {
    func testINaturalistSpeciesCountsDecode() throws {
        // Shape of GET /v1/observations/species_counts (trimmed real response, 2026-11-14).
        let json = """
        {"total_results": 228, "page": 1, "per_page": 1, "results": [{
          "count": 1737,
          "taxon": {
            "id": 4954, "rank": "species", "rank_level": 10, "iconic_taxon_id": 3,
            "ancestor_ids": [48460, 1, 2, 355675, 3, 67566, 4929, 597395, 4950, 4954],
            "is_active": true, "name": "Ardea cinerea", "parent_id": 4950, "extinct": false,
            "default_photo": {
              "id": 73516715, "license_code": "cc-by",
              "attribution": "(c) Frank Sengpiel, some rights reserved (CC BY), uploaded by Frank Sengpiel",
              "url": "https://inaturalist-open-data.s3.amazonaws.com/photos/73516715/square.jpg",
              "original_dimensions": {"height": 1365, "width": 2048}, "flags": [],
              "square_url": "https://inaturalist-open-data.s3.amazonaws.com/photos/73516715/square.jpg",
              "medium_url": "https://inaturalist-open-data.s3.amazonaws.com/photos/73516715/medium.jpg"
            },
            "observations_count": 274510,
            "wikipedia_url": "http://en.wikipedia.org/wiki/Grey_heron",
            "iconic_taxon_name": "Aves", "preferred_common_name": "Grey Heron"
          }
        }]}
        """
        let page = try JSONDecoder().decode(INatPage<INatSpeciesCount>.self, from: Data(json.utf8))
        XCTAssertEqual(page.total_results, 228)
        let t = try XCTUnwrap(page.results.first?.taxon)
        XCTAssertEqual(t.commonName, "Grey Heron")
        XCTAssertEqual(t.group, .birds)
        XCTAssertTrue(t.isSpeciesLevel)
        XCTAssertEqual(t.photoURL?.absoluteString, "https://inaturalist-open-data.s3.amazonaws.com/photos/73516715/medium.jpg")
        XCTAssertEqual(t.default_photo?.sized("large")?.lastPathComponent, "large.jpg")
    }

    func testXenoCantoRecordingDecodeAndLicense() throws {
        // Shape of a Xeno-canto API v3 recording (fields documented at xeno-canto.org/explore/api).
        let json = """
        {"id": "694038", "gen": "Troglodytes", "sp": "troglodytes", "en": "Eurasian Wren",
         "rec": "W.P. Vellinga", "cnt": "Netherlands", "loc": "Amsterdam", "type": "song", "q": "A",
         "length": "0:54", "file": "https://xeno-canto.org/694038/download",
         "lic": "//creativecommons.org/licenses/by-nc-sa/4.0/", "url": "//xeno-canto.org/694038", "date": "2021-12-01"}
        """
        let r = try JSONDecoder().decode(XenoCantoRecording.self, from: Data(json.utf8))
        XCTAssertEqual(r.licenseName, "CC BY-NC-SA 4.0")
        XCTAssertEqual(r.pageURL?.absoluteString, "https://xeno-canto.org/694038")
        XCTAssertEqual(r.fileURL?.host, "xeno-canto.org")
    }

    func testObservationCoordinateOrder() throws {
        let json = """
        {"id": 1, "observed_on": "2026-05-31", "place_guess": "Artis, Amsterdam",
         "geojson": {"type": "Point", "coordinates": [4.9166, 52.3660]},
         "taxon": {"id": 3, "name": "Aves"}, "photos": [], "sounds": [], "user": {"login": "someone"}}
        """
        let o = try JSONDecoder().decode(INatObservation.self, from: Data(json.utf8))
        XCTAssertEqual(o.coordinate?.latitude ?? 0, 52.3660, accuracy: 1e-6)
        XCTAssertEqual(o.coordinate?.longitude ?? 0, 4.9166, accuracy: 1e-6)
        XCTAssertNotNil(o.observedDate)
    }
}
