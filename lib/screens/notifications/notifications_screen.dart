import 'package:flutter/material.dart';

class NotificationsScreen extends StatelessWidget {
  final Map<String, dynamic>? weatherData;
  final String cityName;

  const NotificationsScreen({
    super.key,
    required this.weatherData,
    required this.cityName,
  });

  // ============================================================================
  // CURRENT WEATHER
  // ============================================================================

  Map<String, dynamic>? get _current {
    final data = weatherData?['current'];

    if (data is Map<String, dynamic>) {
      return data;
    }

    return null;
  }

  Map<String, dynamic>? get _daily {
    final data = weatherData?['daily'];

    if (data is Map<String, dynamic>) {
      return data;
    }

    return null;
  }

  double? get _temperature {
    final value = _current?['temperature_2m'];

    if (value is num) {
      return value.toDouble();
    }

    return null;
  }

  int? get _weatherCode {
    final value = _current?['weather_code'];

    if (value is num) {
      return value.toInt();
    }

    return null;
  }

  double? get _rainChance {
    final values = _daily?['precipitation_probability_max'];

    if (values is List &&
        values.isNotEmpty &&
        values[0] is num) {
      return (values[0] as num).toDouble();
    }

    return null;
  }

  double? get _uvIndex {
    final values = _daily?['uv_index_max'];

    if (values is List &&
        values.isNotEmpty &&
        values[0] is num) {
      return (values[0] as num).toDouble();
    }

    return null;
  }

  // ============================================================================
  // WEATHER DESCRIPTION
  // ============================================================================

  String _getWeatherDescription(int? code) {
    if (code == null) {
      return 'Weather information is available.';
    }

    if (code == 0) {
      return 'The sky is clear.';
    }

    if (code == 1 || code == 2) {
      return 'The sky is partly cloudy.';
    }

    if (code == 3) {
      return 'The sky is overcast.';
    }

    if (code >= 45 && code <= 48) {
      return 'Foggy conditions are expected.';
    }

    if (code >= 51 && code <= 57) {
      return 'Light drizzle is expected.';
    }

    if (code >= 61 && code <= 67) {
      return 'Rain is expected today.';
    }

    if (code >= 71 && code <= 77) {
      return 'Snow is expected today.';
    }

    if (code >= 80 && code <= 82) {
      return 'Rain showers are expected today.';
    }

    if (code >= 95) {
      return 'Thunderstorms are possible today.';
    }

    return 'Current weather information is available.';
  }

  // ============================================================================
  // UV DESCRIPTION
  // ============================================================================

  String _getUvTitle(double uv) {
    if (uv >= 11) {
      return 'Extreme UV';
    }

    if (uv >= 8) {
      return 'Very High UV';
    }

    if (uv >= 6) {
      return 'High UV';
    }

    if (uv >= 3) {
      return 'Moderate UV';
    }

    return 'Low UV';
  }

  String _getUvDescription(double uv) {
    if (uv >= 11) {
      return 'UV index is extremely high. Avoid prolonged sun exposure.';
    }

    if (uv >= 8) {
      return 'UV index is very high. Use sun protection and avoid prolonged exposure.';
    }

    if (uv >= 6) {
      return 'UV index is high. Consider using sun protection.';
    }

    if (uv >= 3) {
      return 'UV levels may be moderate today.';
    }

    return 'UV levels are low today.';
  }

  // ============================================================================
  // RAIN DESCRIPTION
  // ============================================================================

  String _getRainTitle(double rain) {
    if (rain >= 80) {
      return 'Heavy Rain Chance';
    }

    if (rain >= 50) {
      return 'High Rain Chance';
    }

    if (rain >= 30) {
      return 'Rain Chance';
    }

    return 'Low Rain Chance';
  }

  String _getRainDescription(double rain) {
    if (rain >= 80) {
      return '${rain.toStringAsFixed(0)}% chance of rain today. Carry an umbrella.';
    }

    if (rain >= 50) {
      return '${rain.toStringAsFixed(0)}% chance of rain today. Consider carrying an umbrella.';
    }

    if (rain >= 30) {
      return '${rain.toStringAsFixed(0)}% chance of rain today.';
    }

    return '${rain.toStringAsFixed(0)}% chance of rain today.';
  }

  // ============================================================================
  // TEMPERATURE DESCRIPTION
  // ============================================================================

  String _getTemperatureDescription(double temperature) {
    if (temperature >= 35) {
      return 'It is very hot today. Stay hydrated and avoid prolonged heat exposure.';
    }

    if (temperature >= 30) {
      return 'Temperatures are warm today. Stay hydrated.';
    }

    if (temperature <= 10) {
      return 'Temperatures are quite low today. Dress warmly.';
    }

    return 'Current temperature is ${temperature.toStringAsFixed(1)}°C.';
  }

  // ============================================================================
  // NOTIFICATION CARD
  // ============================================================================

  Widget _notificationCard({
    required IconData icon,
    required String title,
    required String value,
    required String description,
    bool warning = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: warning
              ? const Color(0xFFFFC66D)
              : Colors.transparent,
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: warning
                  ? const Color(0xFFFFF1DB)
                  : const Color(0xFFE8F2FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: warning
                  ? const Color(0xFFFF9800)
                  : const Color(0xFF4A90E2),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF222222),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    final rain = _rainChance;
    final uv = _uvIndex;
    final temperature = _temperature;
    final weatherCode = _weatherCode;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      body: SafeArea(
        child: Column(
          children: [
            // ================================================================
            // HEADER
            // ================================================================

            Padding(
              padding: const EdgeInsets.fromLTRB(
                20,
                14,
                20,
                8,
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(
                      Icons.arrow_back,
                      size: 28,
                    ),
                    color: Colors.black,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),

            // ================================================================
            // CONTENT
            // ================================================================

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ==========================================================
                    // LOCATION
                    // ==========================================================

                    Padding(
                      padding: const EdgeInsets.only(
                        left: 4,
                        bottom: 14,
                      ),
                      child: Text(
                        cityName.isEmpty
                            ? 'Current Location'
                            : cityName,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    // ==========================================================
                    // RAIN CHANCE
                    // ==========================================================

                    if (rain != null)
                      _notificationCard(
                        icon: Icons.umbrella_outlined,
                        title: _getRainTitle(rain),
                        value:
                            '${rain.toStringAsFixed(0)}%',
                        description:
                            _getRainDescription(rain),
                        warning: rain >= 50,
                      ),

                    // ==========================================================
                    // UV INDEX
                    // ==========================================================

                    if (uv != null)
                      _notificationCard(
                        icon: Icons.wb_sunny_outlined,
                        title: _getUvTitle(uv),
                        value: uv.toStringAsFixed(1),
                        description:
                            _getUvDescription(uv),
                        warning: uv >= 8,
                      ),

                    // ==========================================================
                    // TEMPERATURE
                    // ==========================================================

                    if (temperature != null)
                      _notificationCard(
                        icon: Icons.thermostat_outlined,
                        title: 'Temperature',
                        value:
                            '${temperature.toStringAsFixed(1)}°C',
                        description:
                            _getTemperatureDescription(
                          temperature,
                        ),
                        warning: temperature >= 35 ||
                            temperature <= 10,
                      ),

                    // ==========================================================
                    // WEATHER UPDATE
                    // ==========================================================

                    _notificationCard(
                      icon: Icons.cloud_outlined,
                      title: 'Weather Update',
                      value: 'Now',
                      description:
                          _getWeatherDescription(
                        weatherCode,
                      ),
                    ),

                    // ==========================================================
                    // NO WEATHER DATA
                    // ==========================================================

                    if (weatherData == null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.circular(18),
                        ),
                        child: const Text(
                          'Weather information is not available right now.',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 15,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 