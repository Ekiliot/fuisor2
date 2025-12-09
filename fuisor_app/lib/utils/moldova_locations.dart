/// Moldova locations data for recommendation settings
class MoldovaLocations {
  // List of major cities in Moldova
  static const List<String> cities = [
    'Chișinău',
    'Bălți',
    'Tiraspol',
    'Bender',
    'Cahul',
    'Ungheni',
    'Soroca',
    'Orhei',
    'Comrat',
    'Edineț',
    'Ceadîr-Lunga',
    'Strășeni',
    'Căușeni',
    'Drochia',
    'Hîncești',
    'Florești',
    'Sîngerei',
    'Anenii Noi',
    'Ialoveni',
    'Rezina',
    'Rîbnița',
    'Călărași',
    'Dubăsari',
    'Fălești',
    'Glodeni',
    'Ștefan Vodă',
    'Criuleni',
    'Nisporeni',
    'Ocnița',
    'Dondușeni',
    'Basarabeasca',
    'Taraclia',
    'Leova',
    'Cimișlia',
    'Cantemir',
    'Vulcănești',
  ];

  // Districts (sectors) for each city
  static const Map<String, List<String>> districts = {
    'Chișinău': [
      'Botanica',
      'Centru',
      'Ciocana',
      'Rîșcani',
      'Buiucani',
    ],
    'Bălți': [
      'Centru',
      'Nord',
      'Sud',
      'Est',
      'Vest',
    ],
    'Tiraspol': [
      'Centru',
      'Nord',
      'Sud',
    ],
    'Bender': [
      'Centru',
      'Nord',
      'Sud',
    ],
    // Most other cities don't have official districts
    // but we can add them as needed
  };

  /// Get districts for a given city
  static List<String> getDistrictsForCity(String city) {
    return districts[city] ?? [];
  }

  /// Check if a city has districts
  static bool hasDistricts(String city) {
    return districts.containsKey(city) && districts[city]!.isNotEmpty;
  }

  /// Get all unique districts across all cities
  static List<String> getAllDistricts() {
    final Set<String> allDistricts = {};
    for (final districtList in districts.values) {
      allDistricts.addAll(districtList);
    }
    return allDistricts.toList()..sort();
  }
}

