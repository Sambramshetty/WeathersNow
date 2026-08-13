import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
  // ============================================================================
  // GET WEATHER
  // ============================================================================

  static Future<Map<String, dynamic>> getWeather({
    required double latitude,
    required double longitude,
  }) async {
    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$latitude'
      '&longitude=$longitude'
      '&current=temperature_2m,relative_humidity_2m,apparent_temperature,'
      'is_day,precipitation,weather_code,wind_speed_10m,visibility'
      '&hourly=temperature_2m,weather_code'
      '&daily=weather_code,temperature_2m_max,temperature_2m_min,'
      'precipitation_probability_max,uv_index_max'
      '&timezone=auto',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
        'Failed to load weather data: ${response.statusCode}',
      );
    }
  }

  // ============================================================================
  // SEARCH CITY
  // ============================================================================

  static Future<List<Map<String, dynamic>>> searchCity(
    String city,
  ) async {
    final originalQuery = city.trim();

    if (originalQuery.isEmpty) {
      return [];
    }

    final normalizedQuery = originalQuery.toLowerCase();

    // Handle common Indian city names/aliases.
    String searchName = originalQuery;

    if (normalizedQuery == 'bangalore') {
      searchName = 'Bengaluru';
    } else if (normalizedQuery == 'bombay') {
      searchName = 'Mumbai';
    } else if (normalizedQuery == 'calcutta') {
      searchName = 'Kolkata';
    } else if (normalizedQuery == 'madras') {
      searchName = 'Chennai';
    } else if (normalizedQuery == 'poona') {
      searchName = 'Pune';
    }

    final query = Uri.encodeComponent(searchName);

    final url = Uri.parse(
      'https://geocoding-api.open-meteo.com/v1/search'
      '?name=$query'
      '&count=20'
      '&language=en'
      '&format=json'
      '&countryCode=IN',
    );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to search city: ${response.statusCode}',
      );
    }

    final data = jsonDecode(response.body);

    if (data['results'] == null) {
      return [];
    }

    final results = List<Map<String, dynamic>>.from(
      data['results'],
    );

    // Only Indian results.
    final indianResults = results.where((result) {
      final countryCode =
          result['country_code']?.toString().toUpperCase();

      return countryCode == 'IN';
    }).toList();

    // ============================================================================
    // RELEVANCE SCORING
    // ============================================================================

    int scoreResult(
      Map<String, dynamic> result,
    ) {
      final name =
          result['name']?.toString().toLowerCase() ?? '';

      final featureCode =
          result['feature_code']?.toString().toUpperCase() ?? '';

      final population =
          (result['population'] as num?)?.toInt() ?? 0;

      int score = 0;

      // --------------------------------------------------------------------------
      // Exact match
      // --------------------------------------------------------------------------

      if (name == normalizedQuery) {
        score += 1000;
      }

      // --------------------------------------------------------------------------
      // Exact match with Bengaluru alias
      // --------------------------------------------------------------------------

      if (normalizedQuery == 'bangalore' &&
          name == 'bengaluru') {
        score += 2000;
      }

      if (normalizedQuery == 'bengaluru' &&
          name == 'bengaluru') {
        score += 2000;
      }

      // --------------------------------------------------------------------------
      // Starts with the search text
      // --------------------------------------------------------------------------

      if (name.startsWith(normalizedQuery)) {
        score += 500;
      }

      // --------------------------------------------------------------------------
      // Contains the search text
      // --------------------------------------------------------------------------

      if (name.contains(normalizedQuery)) {
        score += 100;
      }

      // --------------------------------------------------------------------------
      // Prefer actual cities
      // --------------------------------------------------------------------------

      if (featureCode == 'PPLA') {
        score += 300;
      }

      if (featureCode == 'PPLC') {
        score += 500;
      }

      if (featureCode == 'PPL') {
        score += 50;
      }

      // --------------------------------------------------------------------------
      // Population matters
      // --------------------------------------------------------------------------

      if (population > 10000000) {
        score += 300;
      } else if (population > 5000000) {
        score += 250;
      } else if (population > 1000000) {
        score += 200;
      } else if (population > 500000) {
        score += 150;
      } else if (population > 100000) {
        score += 100;
      }

      return score;
    }

    // Sort most relevant first.
    indianResults.sort(
      (a, b) {
        return scoreResult(b).compareTo(
          scoreResult(a),
        );
      },
    );

    // Only show the best 5 results.
    if (indianResults.length > 5) {
      return indianResults.take(5).toList();
    }

    return indianResults;
  }
}
