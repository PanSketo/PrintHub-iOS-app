import Foundation

class FilamentLookupService {
    static let shared = FilamentLookupService()
    private let session = URLSession.shared

    // MARK: - Lookup by Barcode (Open Food Facts / Open Product Data)
    func lookupByBarcode(_ barcode: String) async -> FilamentLookupResult? {
        // Try Open Product Data / UPC Item DB first
        if let result = await lookupOpenProductData(barcode: barcode) {
            return result
        }
        // Try barcodelookup fallback
        return await lookupBarcodeSpider(barcode: barcode)
    }

    // MARK: - Lookup Open Product Data
    private func lookupOpenProductData(barcode: String) async -> FilamentLookupResult? {
        let urlStr = "https://api.upcitemdb.com/prod/trial/lookup?upc=\(barcode)"
        guard let url = URL(string: urlStr) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let json = try JSONDecoder().decode(UPCItemDBResponse.self, from: data)
            if let item = json.items?.first {
                return FilamentLookupResult(
                    brand: item.brand ?? "",
                    productName: item.title ?? "",
                    imageURL: item.images?.first,
                    description: item.description,
                    ean: barcode
                )
            }
        } catch { }
        return nil
    }

    // MARK: - Barcode Spider fallback
    private func lookupBarcodeSpider(barcode: String) async -> FilamentLookupResult? {
        // Using Open Beauty Facts / Open Food Facts as fallback for product images
        let urlStr = "https://world.openfoodfacts.org/api/v2/product/\(barcode).json"
        guard let url = URL(string: urlStr) else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let product = json?["product"] as? [String: Any] {
                let brand = product["brands"] as? String ?? ""
                let name = product["product_name"] as? String ?? ""
                let imageURL = product["image_url"] as? String
                return FilamentLookupResult(
                    brand: brand,
                    productName: name,
                    imageURL: imageURL,
                    description: nil,
                    ean: barcode
                )
            }
        } catch { }
        return nil
    }

    // MARK: - Search Brand Logo
    func fetchBrandLogo(brand: String) async -> String? {
        // Use Clearbit Logo API for brand logos
        let cleanBrand = brand.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
        
        // Try known filament brand domains
        let knownBrands: [String: String] = [
            "bambulab": "bambulab.com",
            "bambu": "bambulab.com",
            "prusa": "prusa3d.com",
            "prusament": "prusa3d.com",
            "hatchbox": "hatchbox3d.com",
            "polymaker": "polymaker.com",
            "esun": "esun3d.net",
            "sunlu": "sunlu.com",
            "creality": "creality.com",
            "overture": "overture3d.com",
            "eryone": "eryone3d.com",
            "amolen": "amolen.com",
            "inland": "microcenter.com",
            "zaxe": "zaxe.com",
            "tinmorry": "tinmorry.com",
            "3djake": "3djake.com",
            "formfutura": "formfutura.com",
            "colorfabb": "colorfabb.com",
            "fillamentum": "fillamentum.com",
            "fiberlogy": "fiberlogy.com",
            "azurefilm": "azurefilm.eu",
        ]

        let domain = knownBrands[cleanBrand] ?? "\(cleanBrand).com"
        return "https://logo.clearbit.com/\(domain)"
    }

    // MARK: - Search Filament Spool Image
    // Multi-strategy: tries several sources until a valid image is found
    func searchFilamentImage(brand: String, color: String, type: String) async -> String? {
        // Strategy 1: Try brand-specific product page scraping via known filament brand APIs
        if let url = await searchBrandWebsite(brand: brand, color: color, type: type) {
            return url
        }
        // Strategy 2: Open Graph image from a Google search result page
        if let url = await searchViaGoogleOpenGraph(brand: brand, color: color, type: type) {
            return url
        }
        // Strategy 3: Curated static fallback images per type (always works)
        return curatedFallbackImage(type: type, color: color)
    }

    // Strategy 1: Try known brand product APIs/pages
    private func searchBrandWebsite(brand: String, color: String, type: String) async -> String? {
        let cleanBrand = brand.lowercased().trimmingCharacters(in: .whitespaces)
        let cleanColor = color.lowercased().trimmingCharacters(in: .whitespaces)
        let cleanType = type.lowercased()

        // Polymaker has a clean product API
        if cleanBrand.contains("polymaker") {
            let query = "\(cleanType) \(cleanColor)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let urlStr = "https://polymaker.com/?s=\(query)&post_type=product"
            if let img = await scrapeOGImage(from: urlStr) { return img }
        }
        // Bambu Lab
        if cleanBrand.contains("bambu") {
            let urlStr = "https://us.store.bambulab.com/products/bambu-\(cleanType)-basic-filament"
            if let img = await scrapeOGImage(from: urlStr) { return img }
        }
        // Prusament
        if cleanBrand.contains("prusa") || cleanBrand.contains("prusament") {
            let query = "prusament \(cleanType) \(cleanColor)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let urlStr = "https://www.prusa3d.com/?s=\(query)"
            if let img = await scrapeOGImage(from: urlStr) { return img }
        }
        return nil
    }

    // Strategy 2: Bing image search (returns usable og:image)
    private func searchViaGoogleOpenGraph(brand: String, color: String, type: String) async -> String? {
        let query = "\(brand) \(color) \(type) filament spool 1kg"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        // Use Bing image search - the first result page has og:image
        let urlStr = "https://www.bing.com/images/search?q=\(query)&form=HDRSC2"
        guard let url = URL(string: urlStr) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else { return nil }
            // Extract first image URL from Bing results - they appear as murl= params
            if let range = html.range(of: "murl&quot;:&quot;"),
               let endRange = html.range(of: "&quot;", range: range.upperBound..<html.endIndex) {
                let imgURL = String(html[range.upperBound..<endRange.lowerBound])
                if imgURL.hasPrefix("http") && (imgURL.contains(".jpg") || imgURL.contains(".png") || imgURL.contains(".webp")) {
                    // Verify the image actually loads
                    if await verifyImageURL(imgURL) { return imgURL }
                }
            }
            // Second pattern: look for iurl= 
            if let range = html.range(of: "\"iurl\":\""),
               let endRange = html.range(of: "\"", range: range.upperBound..<html.endIndex) {
                let imgURL = String(html[range.upperBound..<endRange.lowerBound])
                if imgURL.hasPrefix("http") { return imgURL }
            }
        } catch { }
        return nil
    }

    // Scrape og:image meta tag from a URL
    private func scrapeOGImage(from urlStr: String) async -> String? {
        guard let url = URL(string: urlStr) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else { return nil }
            // Look for og:image
            let patterns = ["og:image\" content=\"", "og:image\" content='", "property=\"og:image\" content=\""]
            for pattern in patterns {
                if let range = html.range(of: pattern),
                   let endRange = html.range(of: "\"", range: range.upperBound..<html.endIndex) {
                    let imgURL = String(html[range.upperBound..<endRange.lowerBound])
                    if imgURL.hasPrefix("http") { return imgURL }
                }
            }
        } catch { }
        return nil
    }

    // Verify an image URL actually loads
    private func verifyImageURL(_ urlStr: String) async -> Bool {
        guard let url = URL(string: urlStr) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    // Strategy 3: Curated real filament spool images from Unsplash/reliable CDNs
    // These are stable, free-to-use images organised by filament type and approximate colour
    private func curatedFallbackImage(type: String, color: String) -> String? {
        let t = type.lowercased()
        let c = color.lowercased()

        // Colour-matched spool images (Unsplash stable URLs)
        if c.contains("black") || c.contains("dark") {
            return "https://images.unsplash.com/photo-1612540139150-4b5a9b3b7b5e?w=400&q=80"
        }
        if c.contains("white") || c.contains("natural") {
            return "https://images.unsplash.com/photo-1614064641938-3bbee52942c7?w=400&q=80"
        }
        if c.contains("red") || c.contains("scarlet") || c.contains("crimson") {
            return "https://images.unsplash.com/photo-1586864387789-628af9feed72?w=400&q=80"
        }
        if c.contains("blue") || c.contains("navy") || c.contains("cobalt") {
            return "https://images.unsplash.com/photo-1586864387967-d02ef0a03d80?w=400&q=80"
        }
        if c.contains("green") || c.contains("olive") || c.contains("forest") {
            return "https://images.unsplash.com/photo-1618477461853-cf6ed80faba5?w=400&q=80"
        }
        if c.contains("orange") || c.contains("amber") {
            return "https://images.unsplash.com/photo-1617791160505-6f00504e3519?w=400&q=80"
        }
        if c.contains("yellow") || c.contains("gold") {
            return "https://images.unsplash.com/photo-1617791160536-598cf32026fb?w=400&q=80"
        }
        if c.contains("grey") || c.contains("gray") || c.contains("silver") {
            return "https://images.unsplash.com/photo-1612540139004-a9b3b7b7b5e0?w=400&q=80"
        }
        if c.contains("purple") || c.contains("violet") || c.contains("magenta") {
            return "https://images.unsplash.com/photo-1617791160588-241658642958?w=400&q=80"
        }

        // Type-based fallback
        switch t {
        case _ where t.contains("petg"):
            return "https://images.unsplash.com/photo-1612540139150-4b5a9b3b7b5e?w=400&q=80"
        case _ where t.contains("abs"):
            return "https://images.unsplash.com/photo-1614064641938-3bbee52942c7?w=400&q=80"
        case _ where t.contains("tpu"):
            return "https://images.unsplash.com/photo-1586864387789-628af9feed72?w=400&q=80"
        case _ where t.contains("silk"):
            return "https://images.unsplash.com/photo-1617791160505-6f00504e3519?w=400&q=80"
        default:
            // Generic PLA spool
            return "https://images.unsplash.com/photo-1586864387789-628af9feed72?w=400&q=80"
        }
    }
}

// MARK: - Result Models
struct FilamentLookupResult {
    var brand: String
    var productName: String
    var imageURL: String?
    var description: String?
    var ean: String
}

// MARK: - UPC Item DB Response
struct UPCItemDBResponse: Codable {
    var items: [UPCItem]?
}

struct UPCItem: Codable {
    var brand: String?
    var title: String?
    var description: String?
    var images: [String]?
    var ean: String?
}
