// lib/services/map_tile_service.dart
// Map tile source definitions — 3 sources, no API key required

enum MapTileSource {
  openStreetMap, // OSM standard — default
  openTopoMap,   // Topo layer — field/hiking
  satellite,     // ESRI World Imagery — satellite
}

class MapTileService {
  /// Tile URL template for use with flutter_map TileLayer urlTemplate.
  /// All sources use standard slippy map z/x/y convention except ESRI (z/y/x).
  static String urlTemplate(MapTileSource source) {
    switch (source) {
      case MapTileSource.openStreetMap:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapTileSource.openTopoMap:
        return 'https://tile.opentopomap.org/{z}/{x}/{y}.png';
      case MapTileSource.satellite:
        // ESRI World Imagery — free, no API key, note y/x order
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
            'World_Imagery/MapServer/tile/{z}/{y}/{x}';
    }
  }

  /// Resolved tile URL for manual download (replace z/x/y placeholders).
  static String tileUrl(MapTileSource source, int z, int x, int y) {
    return urlTemplate(source)
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y');
  }

  static String label(MapTileSource source) {
    switch (source) {
      case MapTileSource.openStreetMap: return 'Street';
      case MapTileSource.openTopoMap:  return 'Topo';
      case MapTileSource.satellite:    return 'Satellite';
    }
  }

  static String icon(MapTileSource source) {
    switch (source) {
      case MapTileSource.openStreetMap: return '🗺';
      case MapTileSource.openTopoMap:  return '🏔';
      case MapTileSource.satellite:    return '🛰';
    }
  }

  static MapTileSource fromName(String name) {
    return MapTileSource.values.firstWhere(
      (s) => s.name == name,
      orElse: () => MapTileSource.openStreetMap,
    );
  }
}
