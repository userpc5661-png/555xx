/// Map styles shown on the map page.
class MapConfig {
  const MapConfig._();

  /// Street map (OpenStreetMap data, no key).
  static const String streetStyle =
      'https://tiles.openfreemap.org/styles/liberty';

  // MapTiler key of the driver's own account. Restrict it to this app in
  // the MapTiler dashboard.
  static const String _mapTilerKey = 'B8YbOHvTizKgUzgykWwF';

  /// High-resolution satellite photos with street and area names on top,
  /// so buildings missing from the street map are visible.
  static const String satelliteStyle =
      'https://api.maptiler.com/maps/hybrid-v4/style.json?key=$_mapTilerKey';
}
