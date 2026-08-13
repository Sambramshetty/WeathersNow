import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../services/weather_service.dart';
import '../notifications/notifications_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? weatherData;
  double? visibilityKm;

  bool isLoading = true;
  bool isSearching = false;
  bool isGettingLocation = false;

  String? errorMessage;

  String cityName = 'Bengaluru';

  double currentLatitude = 12.9716;
  double currentLongitude = 77.5946;

  final TextEditingController _searchController =
      TextEditingController();

  List<Map<String, dynamic>> citySuggestions = [];

  @override
  void initState() {
    super.initState();
    _loadSavedCity();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // CITY KEY
  // ============================================================

  String _cityKey(String name) {
    var key = name.trim().toLowerCase();

    if (key == 'bangalore') {
      key = 'bengaluru';
    }

    return key.replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
  }

  // ============================================================
  // LOAD SAVED SELECTED CITY
  // ============================================================

  Future<void> _loadSavedCity() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;

          final savedCity =
              data['selectedCity']?.toString();

          final latitude =
              (data['latitude'] as num?)?.toDouble();

          final longitude =
              (data['longitude'] as num?)?.toDouble();

          if (savedCity != null &&
              savedCity.isNotEmpty &&
              latitude != null &&
              longitude != null) {
            cityName = savedCity;
            currentLatitude = latitude;
            currentLongitude = longitude;
          }
        }
      }
    } catch (e) {
      debugPrint('Load selected city error: $e');
    }

    await _loadWeather();
    await _loadSavedCityStatus();
  }

  // ============================================================
  // SAVE SELECTED CITY
  // ============================================================

  Future<void> _saveCityToFirestore({
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(
        {
          'selectedCity': name,
          'latitude': latitude,
          'longitude': longitude,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Save selected city error: $e');
    }
  }

  // ============================================================
  // CHECK IF CURRENT CITY IS SAVED
  // ============================================================

  Future<void> _loadSavedCityStatus() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null ||
        cityName == 'Current Location') {
      if (mounted) {
        setState(() {
          _isCurrentCitySaved = false;
        });
      }
      return;
    }

    try {
      final collection = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('savedCities');

      final key = _cityKey(cityName);

      final fixedDoc =
          await collection.doc(key).get();

      bool saved = fixedDoc.exists;

      if (!saved) {
        final snapshot =
            await collection.get();

        saved = snapshot.docs.any((doc) {
          final name =
              doc.data()['name']?.toString() ?? '';

          return _cityKey(name) == key;
        });
      }

      if (!mounted) return;

      setState(() {
        _isCurrentCitySaved = saved;
      });
    } catch (e) {
      debugPrint('Saved city status error: $e');

      if (!mounted) return;

      setState(() {
        _isCurrentCitySaved = false;
      });
    }
  }

  bool _isCurrentCitySaved = false;

  // ============================================================
  // SAVE / UNSAVE CITY
  // ============================================================

  Future<void> _toggleSavedCity() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage(
        'Please log in to save cities.',
      );
      return;
    }

    if (cityName == 'Current Location') {
      _showMessage(
        'Select a city before saving it.',
      );
      return;
    }

    final collection = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('savedCities');

    final key = _cityKey(cityName);

    try {
      // ----------------------------------------------------------
      // CHECK FIXED DOCUMENT
      // ----------------------------------------------------------

      final fixedDoc =
          await collection.doc(key).get();

      if (fixedDoc.exists) {
        // Already saved -> REMOVE IT.
        await fixedDoc.reference.delete();

        // Remove any old duplicate documents too.
        final snapshot =
            await collection.get();

        for (final doc in snapshot.docs) {
          if (doc.id == key) {
            continue;
          }

          final name =
              doc.data()['name']?.toString() ?? '';

          if (_cityKey(name) == key) {
            await doc.reference.delete();
          }
        }

        if (!mounted) return;

        setState(() {
          _isCurrentCitySaved = false;
        });

        _showMessage(
          '$cityName removed from saved cities.',
        );

        return;
      }

      // ----------------------------------------------------------
      // CHECK OLD DOCUMENTS
      // ----------------------------------------------------------

      final snapshot =
          await collection.get();

      final oldMatches =
          snapshot.docs.where((doc) {
        final name =
            doc.data()['name']?.toString() ?? '';

        return _cityKey(name) == key;
      }).toList();

      if (oldMatches.isNotEmpty) {
        // Old city exists -> remove all duplicates.
        for (final doc in oldMatches) {
          await doc.reference.delete();
        }

        if (!mounted) return;

        setState(() {
          _isCurrentCitySaved = false;
        });

        _showMessage(
          '$cityName removed from saved cities.',
        );

        return;
      }

      // ----------------------------------------------------------
      // CITY NOT SAVED -> SAVE IT
      // ----------------------------------------------------------

      await collection.doc(key).set({
        'name': cityName,
        'latitude': currentLatitude,
        'longitude': currentLongitude,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      setState(() {
        _isCurrentCitySaved = true;
      });

      _showMessage(
        '$cityName saved successfully!',
      );
    } catch (e) {
      debugPrint(
        'Toggle saved city error: $e',
      );

      if (!mounted) return;

      _showMessage(
        'Could not update saved city. Please try again.',
      );
    }
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration:
              const Duration(seconds: 2),
          behavior:
              SnackBarBehavior.floating,
        ),
      );
  }

  // ============================================================
  // CITY SEARCH
  // ============================================================

  Future<void> _searchCities(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        citySuggestions = [];
        isSearching = false;
      });
      return;
    }

    setState(() {
      isSearching = true;
    });

    try {
      final results =
          await WeatherService.searchCity(
        query.trim(),
      );

      if (!mounted) return;

      setState(() {
        citySuggestions = results;
        isSearching = false;
      });
    } catch (e) {
      debugPrint(
        'City search error: $e',
      );

      if (!mounted) return;

      setState(() {
        citySuggestions = [];
        isSearching = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    if (value.trim().length < 2) {
      setState(() {
        citySuggestions = [];
      });
      return;
    }

    _searchCities(value);
  }

  // ============================================================
  // SELECT CITY
  // ============================================================

  Future<void> _selectCity(
    Map<String, dynamic> city,
  ) async {
    final name =
        city['name']?.toString() ?? 'Unknown';

    final latitude =
        (city['latitude'] as num?)?.toDouble();

    final longitude =
        (city['longitude'] as num?)?.toDouble();

    if (latitude == null ||
        longitude == null) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      cityName = name;
      currentLatitude = latitude;
      currentLongitude = longitude;
      citySuggestions = [];
      _searchController.clear();
    });

    await _saveCityToFirestore(
      name: name,
      latitude: latitude,
      longitude: longitude,
    );

    await _loadWeather();
    await _loadSavedCityStatus();
  }

  // ============================================================
  // CURRENT LOCATION
  // ============================================================

  Future<void> _getCurrentLocation() async {
    if (isGettingLocation) return;

    setState(() {
      isGettingLocation = true;
      errorMessage = null;
    });

    try {
      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        throw Exception(
          'Location services are turned off.',
        );
      }

      var permission =
          await Geolocator.checkPermission();

      if (permission ==
          LocationPermission.denied) {
        permission =
            await Geolocator.requestPermission();
      }

      if (permission ==
          LocationPermission.denied) {
        throw Exception(
          'Location permission was denied.',
        );
      }

      if (permission ==
          LocationPermission.deniedForever) {
        throw Exception(
          'Location permission is permanently denied.',
        );
      }

      final position =
          await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(
          accuracy:
              LocationAccuracy.high,
        ),
      );

      currentLatitude =
          position.latitude;

      currentLongitude =
          position.longitude;

      if (!mounted) return;

      setState(() {
        cityName = 'Current Location';
        isGettingLocation = false;
      });

      await _loadWeather();
      await _loadSavedCityStatus();
    } catch (e) {
      debugPrint(
        'Location error: $e',
      );

      if (!mounted) return;

      setState(() {
        isGettingLocation = false;
        errorMessage =
            e.toString().replaceFirst(
                  'Exception: ',
                  '',
                );
      });
    }
  }

  // ============================================================
  // WEATHER
  // ============================================================

  Future<void> _loadWeather() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final data =
          await WeatherService.getWeather(
        latitude: currentLatitude,
        longitude: currentLongitude,
      );

      if (!mounted) return;

      setState(() {
        weatherData = data;
        isLoading = false;
      });

      await _loadVisibility();
    } catch (e) {
      debugPrint(
        'Weather error: $e',
      );

      if (!mounted) return;

      setState(() {
        isLoading = false;
        errorMessage =
            'Unable to load weather.';
      });
    }
  }

  // ============================================================
  // CURRENT VISIBILITY
  // ============================================================

  Future<void> _loadVisibility() async {
    try {
      final uri = Uri.https(
        'api.open-meteo.com',
        '/v1/forecast',
        {
          'latitude': currentLatitude.toString(),
          'longitude': currentLongitude.toString(),
          'current': 'visibility',
        },
      );

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception('Visibility request failed');
      }

      final data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final current =
          data['current'] as Map<String, dynamic>?;
      final visibility =
          (current?['visibility'] as num?)?.toDouble();

      if (!mounted) return;

      setState(() {
        visibilityKm =
            visibility == null ? null : visibility / 1000.0;
      });
    } catch (e) {
      debugPrint('Visibility error: $e');

      if (!mounted) return;

      setState(() {
        visibilityKm = null;
      });
    }
  }

  // ============================================================
  // NOTIFICATIONS
  // ============================================================

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            NotificationsScreen(
          weatherData: weatherData,
          cityName: cityName,
        ),
      ),
    );
  }

  // ============================================================
  // SAVED CITIES
  // ============================================================

  void _openSavedCities() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SavedCitiesScreen(
          onCitySelected: _selectCity,
        ),
      ),
    ).then(
      (_) => _loadSavedCityStatus(),
    );
  }

  // ============================================================
  // WEATHER DESCRIPTION
  // ============================================================

  String _getWeatherDescription(int code) {
    if (code == 0) {
      return 'Clear Sky';
    }

    if (code <= 2) {
      return 'Partly Cloudy';
    }

    if (code == 3) {
      return 'Overcast';
    }

    if (code <= 48) {
      return 'Foggy';
    }

    if (code <= 57) {
      return 'Drizzle';
    }

    if (code <= 67) {
      return 'Rain';
    }

    if (code <= 77) {
      return 'Snow';
    }

    if (code <= 82) {
      return 'Rain Showers';
    }

    return 'Thunderstorm';
  }

  // ============================================================
  // WEATHER ICON
  // ============================================================

  IconData _getWeatherIcon(int code) {
    if (code == 0) {
      return Icons.wb_sunny_rounded;
    }

    if (code <= 2) {
      return Icons.cloud_queue_rounded;
    }

    if (code == 3) {
      return Icons.cloud_rounded;
    }

    if (code <= 48) {
      return Icons.foggy;
    }

    if (code <= 57) {
      return Icons.grain_rounded;
    }

    if (code <= 67) {
      return Icons.water_drop_rounded;
    }

    if (code <= 77) {
      return Icons.ac_unit_rounded;
    }

    if (code <= 82) {
      return Icons.grain_rounded;
    }

    return Icons.thunderstorm_rounded;
  }

  // ============================================================
  // HOURLY FORECAST
  // ============================================================

  Widget _buildHourlyForecast() {
    final hourly =
        weatherData?['hourly'];

    if (hourly == null) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    final times =
        List<String>.from(
      hourly['time'] ?? [],
    );

    final temperatures =
        List<dynamic>.from(
      hourly['temperature_2m'] ?? [],
    );

    final codes =
        List<dynamic>.from(
      hourly['weather_code'] ?? [],
    );

    if (times.isEmpty ||
        temperatures.isEmpty ||
        codes.isEmpty) {
      return const Center(
        child: Text(
          'No forecast available',
        ),
      );
    }

    final now = DateTime.now();

    int startIndex = 0;

    for (int i = 0;
        i < times.length;
        i++) {
      final time =
          DateTime.parse(times[i]);

      if (!time.isBefore(now)) {
        startIndex = i;
        break;
      }
    }

    final endIndex =
        (startIndex + 8) > times.length
            ? times.length
            : startIndex + 8;

    return ListView.builder(
      scrollDirection:
          Axis.horizontal,
      itemCount:
          endIndex - startIndex,
      itemBuilder:
          (context, index) {
        final actualIndex =
            startIndex + index;

        final time =
            DateTime.parse(
          times[actualIndex],
        );

        final temperature =
            (temperatures[actualIndex]
                    as num)
                .toDouble();

        final code =
            (codes[actualIndex] as num)
                .toInt();

        final timeText =
            index == 0
                ? 'Now'
                : TimeOfDay
                    .fromDateTime(
                    time,
                  ).format(context);

        return _ForecastCard(
          time: timeText,
          temperature:
              '${temperature.toStringAsFixed(0)}°',
          icon:
              _getWeatherIcon(code),
        );
      },
    );
  }

  // ============================================================
  // DAILY FORECAST
  // ============================================================

  Widget _buildDailyForecast() {
    final daily =
        weatherData?['daily'];

    if (daily == null) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    final dates =
        List<String>.from(
      daily['time'] ?? [],
    );

    final maxTemperatures =
        List<dynamic>.from(
      daily[
              'temperature_2m_max'] ??
          [],
    );

    final minTemperatures =
        List<dynamic>.from(
      daily[
              'temperature_2m_min'] ??
          [],
    );

    final codes =
        List<dynamic>.from(
      daily['weather_code'] ?? [],
    );

    final count =
        dates.length > 7
            ? 7
            : dates.length;

    if (count == 0) {
      return const Text(
        'No daily forecast available',
      );
    }

    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    return SizedBox(
      height: 145,
      child: ListView.builder(
        scrollDirection:
            Axis.horizontal,
        itemCount: count,
        itemBuilder:
            (context, index) {
          final date =
              DateTime.parse(
            dates[index],
          );

          final maxTemp =
              (maxTemperatures[index]
                      as num)
                  .toDouble();

          final minTemp =
              (minTemperatures[index]
                      as num)
                  .toDouble();

          final code =
              (codes[index] as num)
                  .toInt();

          final day =
              index == 0
                  ? 'Today'
                  : index == 1
                      ? 'Tomorrow'
                      : days[
                          date.weekday - 1];

          return Container(
            width: 115,
            margin:
                const EdgeInsets.only(
              right: 12,
            ),
            padding:
                const EdgeInsets.all(
              14,
            ),
            decoration:
                BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.circular(
                18,
              ),
              boxShadow: const [
                BoxShadow(
                  color:
                      Colors.black12,
                  blurRadius: 8,
                  offset:
                      Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment
                      .spaceAround,
              children: [
                Text(
                  day,
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Icon(
                  _getWeatherIcon(
                    code,
                  ),
                  color:
                      const Color(
                    0xFF4A90E2,
                  ),
                  size: 30,
                ),
                Text(
                  '${maxTemp.toStringAsFixed(0)}° / '
                  '${minTemp.toStringAsFixed(0)}°',
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // RAIN CHANCE
  // ============================================================

  String _getRainChance() {
    final daily =
        weatherData?['daily'];

    if (daily == null) return '--';

    final values =
        List<dynamic>.from(
      daily[
              'precipitation_probability_max'] ??
          [],
    );

    if (values.isEmpty ||
        values[0] == null) {
      return '--';
    }

    return '${values[0]}%';
  }

  // ============================================================
  // UV INDEX
  // ============================================================

  String _getUvIndex() {
    final daily =
        weatherData?['daily'];

    if (daily == null) return '--';

    final values =
        List<dynamic>.from(
      daily['uv_index_max'] ?? [],
    );

    if (values.isEmpty ||
        values[0] == null) {
      return '--';
    }

    final uv =
        (values[0] as num).toDouble();

    if (uv <= 2) {
      return 'Low';
    }

    if (uv <= 5) {
      return 'Moderate';
    }

    if (uv <= 7) {
      return 'High';
    }

    if (uv <= 10) {
      return 'Very High';
    }

    return 'Extreme';
  }

  // ============================================================
  // SEARCH BOX
  // ============================================================

  Widget _buildSearchBox() {
    return Column(
      children: [
        Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 16,
                ),
                decoration:
                    BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(
                    16,
                  ),
                ),
                child: TextField(
                  controller:
                      _searchController,
                  onChanged:
                      _onSearchChanged,
                  decoration:
                      InputDecoration(
                    icon: const Icon(
                      Icons.search,
                    ),
                    hintText:
                        'Search city...',
                    border:
                        InputBorder.none,
                    suffixIcon:
                        isSearching
                            ? const Padding(
                                padding:
                                    EdgeInsets.all(
                                  12,
                                ),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth:
                                        2,
                                  ),
                                ),
                              )
                            : null,
                  ),
                ),
              ),
            ),
            const SizedBox(
              width: 12,
            ),
            Container(
              height: 56,
              width: 56,
              decoration:
                  BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(
                  16,
                ),
                boxShadow: const [
                  BoxShadow(
                    color:
                        Colors.black12,
                    blurRadius: 10,
                    offset:
                        Offset(0, 4),
                  ),
                ],
              ),
              child: IconButton(
                icon: isGettingLocation
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons
                            .my_location_rounded,
                        color:
                            Color(
                          0xFF4A90E2,
                        ),
                        size: 27,
                      ),
                onPressed:
                    isGettingLocation
                        ? null
                        : _getCurrentLocation,
              ),
            ),
          ],
        ),

        if (citySuggestions
            .isNotEmpty)
          Container(
            margin:
                const EdgeInsets.only(
              top: 6,
            ),
            decoration:
                BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.circular(
                16,
              ),
              boxShadow: const [
                BoxShadow(
                  color:
                      Colors.black12,
                  blurRadius: 10,
                  offset:
                      Offset(0, 4),
                ),
              ],
            ),
            child:
                ListView.separated(
              shrinkWrap: true,
              physics:
                  const NeverScrollableScrollPhysics(),
              itemCount:
                  citySuggestions.length,
              separatorBuilder:
                  (_, _) =>
                      const Divider(
                height: 1,
              ),
              itemBuilder:
                  (context, index) {
                final city =
                    citySuggestions[
                        index];

                final name =
                    city['name']
                            ?.toString() ??
                        'Unknown';

                final state =
                    city['admin1']
                            ?.toString() ??
                        '';

                final country =
                    city['country']
                            ?.toString() ??
                        '';

                return ListTile(
                  leading:
                      const CircleAvatar(
                    backgroundColor:
                        Color(
                      0xFFE8F2FF,
                    ),
                    child: Icon(
                      Icons
                          .location_city,
                      color:
                          Color(
                        0xFF4A90E2,
                      ),
                    ),
                  ),
                  title: Text(
                    name,
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  subtitle:
                      Text(
                    [
                      if (state
                          .isNotEmpty)
                        state,
                      if (country
                          .isNotEmpty)
                        country,
                    ].join(', '),
                  ),
                  trailing:
                      const Icon(
                    Icons
                        .chevron_right,
                  ),
                  onTap: () =>
                      _selectCity(
                    city,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final current =
        weatherData?['current'];

    final temperature =
        current?['temperature_2m'];

    final humidity =
        current?[
            'relative_humidity_2m'];

    final windSpeed =
        current?['wind_speed_10m'];

    final weatherCode =
        current?['weather_code'];

    return Scaffold(
      backgroundColor:
          const Color(0xFFF5F9FF),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh:
              _loadWeather,
          child:
              SingleChildScrollView(
            physics:
                const AlwaysScrollableScrollPhysics(),
            padding:
                const EdgeInsets.all(
              20,
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                // ==========================================================
                // HEADER
                // ==========================================================

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          const Text(
                            'Good morning 👋',
                            style:
                                TextStyle(
                              fontSize: 16,
                              color:
                                  Colors.grey,
                            ),
                          ),
                          const SizedBox(
                            height: 4,
                          ),
                          Text(
                            cityName,
                            style:
                                const TextStyle(
                              fontSize: 28,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // STAR
                    Container(
                      decoration:
                          BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(
                          14,
                        ),
                        boxShadow:
                            const [
                          BoxShadow(
                            color:
                                Colors.black12,
                            blurRadius: 10,
                            offset:
                                Offset(
                              0,
                              4,
                            ),
                          ),
                        ],
                      ),
                      child:
                          IconButton(
                        tooltip:
                            _isCurrentCitySaved
                                ? 'Remove saved city'
                                : 'Save city',
                        icon:
                            Icon(
                          _isCurrentCitySaved
                              ? Icons
                                  .star_rounded
                              : Icons
                                  .star_border_rounded,
                          color:
                              _isCurrentCitySaved
                                  ? const Color(
                                      0xFFFFB300,
                                    )
                                  : Colors
                                      .black87,
                          size: 27,
                        ),
                        onPressed:
                            _toggleSavedCity,
                      ),
                    ),

                    const SizedBox(
                      width: 8,
                    ),

                    // BOOKMARK
                    Container(
                      decoration:
                          BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(
                          14,
                        ),
                        boxShadow:
                            const [
                          BoxShadow(
                            color:
                                Colors.black12,
                            blurRadius: 10,
                            offset:
                                Offset(
                              0,
                              4,
                            ),
                          ),
                        ],
                      ),
                      child:
                          IconButton(
                        tooltip:
                            'Saved cities',
                        icon:
                            const Icon(
                          Icons
                              .bookmark_border_rounded,
                          size: 27,
                        ),
                        onPressed:
                            _openSavedCities,
                      ),
                    ),

                    const SizedBox(
                      width: 8,
                    ),

                    // NOTIFICATIONS
                    Container(
                      decoration:
                          BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(
                          14,
                        ),
                        boxShadow:
                            const [
                          BoxShadow(
                            color:
                                Colors.black12,
                            blurRadius: 10,
                            offset:
                                Offset(
                              0,
                              4,
                            ),
                          ),
                        ],
                      ),
                      child:
                          IconButton(
                        tooltip:
                            'Notifications',
                        icon:
                            const Icon(
                          Icons
                              .notifications_none_rounded,
                          size: 27,
                        ),
                        onPressed:
                            _openNotifications,
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  height: 24,
                ),

                _buildSearchBox(),

                const SizedBox(
                  height: 24,
                ),

                // ==========================================================
                // CURRENT WEATHER
                // ==========================================================

                Container(
                  width:
                      double.infinity,
                  padding:
                      const EdgeInsets.all(
                    24,
                  ),
                  decoration:
                      BoxDecoration(
                    gradient:
                        const LinearGradient(
                      colors: [
                        Color(
                          0xFF4A90E2,
                        ),
                        Color(
                          0xFF70C8E8,
                        ),
                      ],
                      begin:
                          Alignment.topLeft,
                      end:
                          Alignment.bottomRight,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      28,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            Colors.blue
                                .withValues(
                          alpha: 0.25,
                        ),
                        blurRadius:
                            20,
                        offset:
                            const Offset(
                          0,
                          10,
                        ),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      const Text(
                        'Current Weather',
                        style:
                            TextStyle(
                          color:
                              Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              Text(
                                isLoading ||
                                        temperature ==
                                            null
                                    ? '--°'
                                    : '${(temperature as num).toDouble().toStringAsFixed(1)}°',
                                style:
                                    const TextStyle(
                                  color:
                                      Colors.white,
                                  fontSize:
                                      64,
                                  fontWeight:
                                      FontWeight
                                          .bold,
                                ),
                              ),
                              Text(
                                isLoading ||
                                        weatherCode ==
                                            null
                                    ? 'Loading...'
                                    : _getWeatherDescription(
                                        (weatherCode
                                                as num)
                                            .toInt(),
                                      ),
                                style:
                                    const TextStyle(
                                  color:
                                      Colors.white,
                                  fontSize:
                                      18,
                                  fontWeight:
                                      FontWeight
                                          .w500,
                                ),
                              ),
                            ],
                          ),
                          Icon(
                            isLoading ||
                                    weatherCode ==
                                        null
                                ? Icons
                                    .cloud_queue
                                : _getWeatherIcon(
                                    (weatherCode
                                            as num)
                                        .toInt(),
                                  ),
                            color:
                                Colors.white,
                            size: 90,
                          ),
                        ],
                      ),
                      const SizedBox(
                        height: 20,
                      ),
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .spaceBetween,
                        children: [
                          _WeatherInfo(
                            icon: Icons
                                .water_drop_outlined,
                            label:
                                'Humidity',
                            value:
                                humidity ==
                                        null
                                    ? '--'
                                    : '${(humidity as num).round()}%',
                          ),
                          _WeatherInfo(
                            icon:
                                Icons.air,
                            label:
                                'Wind',
                            value:
                                windSpeed ==
                                        null
                                    ? '--'
                                    : '${(windSpeed as num).toDouble().toStringAsFixed(1)} km/h',
                          ),
                          _WeatherInfo(
                            icon: Icons
                                .visibility_outlined,
                            label:
                                'Visibility',
                            value:
                                visibilityKm == null
                                    ? '--'
                                    : '${visibilityKm!.toStringAsFixed(1)} km',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                if (errorMessage !=
                    null) ...[
                  const SizedBox(
                    height: 12,
                  ),
                  Center(
                    child: Text(
                      errorMessage!,
                      textAlign:
                          TextAlign.center,
                      style:
                          const TextStyle(
                        color:
                            Colors.red,
                      ),
                    ),
                  ),
                ],

                const SizedBox(
                  height: 28,
                ),

                const Text(
                  "Today's Forecast",
                  style:
                      TextStyle(
                    fontSize: 20,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 14,
                ),

                SizedBox(
                  height: 130,
                  child:
                      _buildHourlyForecast(),
                ),

                const SizedBox(
                  height: 28,
                ),

                const Text(
                  '7-Day Forecast',
                  style:
                      TextStyle(
                    fontSize: 20,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 14,
                ),

                _buildDailyForecast(),

                const SizedBox(
                  height: 28,
                ),

                const Text(
                  'Weather Insights',
                  style:
                      TextStyle(
                    fontSize: 20,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 14,
                ),

                Row(
                  children: [
                    Expanded(
                      child:
                          _InsightCard(
                        icon: Icons
                            .umbrella_outlined,
                        title:
                            'Rain Chance',
                        value:
                            _getRainChance(),
                      ),
                    ),
                    const SizedBox(
                      width: 12,
                    ),
                    Expanded(
                      child:
                          _InsightCard(
                        icon: Icons
                            .wb_sunny_outlined,
                        title:
                            'UV Index',
                        value:
                            _getUvIndex(),
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  height: 20,
                ),

                Center(
                  child:
                      TextButton.icon(
                    onPressed:
                        _loadWeather,
                    icon:
                        const Icon(
                      Icons.refresh,
                    ),
                    label:
                        const Text(
                      'Refresh Weather',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SAVED CITIES SCREEN
// ============================================================================

class SavedCitiesScreen
    extends StatelessWidget {
  final Future<void> Function(
    Map<String, dynamic> city,
  ) onCitySelected;

  const SavedCitiesScreen({
    super.key,
    required this.onCitySelected,
  });

  String _normalizeCity(
    String name,
  ) {
    var key =
        name.trim().toLowerCase();

    if (key == 'bangalore') {
      key = 'bengaluru';
    }

    return key;
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final user =
        FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Please log in.',
          ),
        ),
      );
    }

    final collection =
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('savedCities');

    return Scaffold(
      backgroundColor:
          const Color(0xFFF5F9FF),
      appBar: AppBar(
        backgroundColor:
            const Color(0xFFF5F9FF),
        elevation: 0,
        title: const Text(
          'Saved Cities',
          style:
              TextStyle(
            color: Colors.black,
            fontWeight:
                FontWeight.bold,
          ),
        ),
        iconTheme:
            const IconThemeData(
          color: Colors.black,
        ),
      ),
      body: StreamBuilder<
          QuerySnapshot<
              Map<String, dynamic>>>(
        stream:
            collection.snapshots(),
        builder:
            (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Unable to load saved cities.',
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child:
                  CircularProgressIndicator(),
            );
          }

          final docs =
              snapshot.data!.docs;

          final seen =
              <String>{};

          final uniqueDocs =
              docs.where((doc) {
            final name =
                doc.data()['name']
                        ?.toString() ??
                    '';

            final key =
                _normalizeCity(name);

            if (name.isEmpty ||
                !seen.add(key)) {
              return false;
            }

            return true;
          }).toList();

          if (uniqueDocs.isEmpty) {
            return const Center(
              child: Text(
                'No saved cities yet.\nTap ⭐ on Home to save a city.',
                textAlign:
                    TextAlign.center,
              ),
            );
          }

          return ListView.separated(
            padding:
                const EdgeInsets.all(
              20,
            ),
            itemCount:
                uniqueDocs.length,
            separatorBuilder:
                (_, _) =>
                    const SizedBox(
              height: 12,
            ),
            itemBuilder:
                (context, index) {
              final data =
                  uniqueDocs[index]
                      .data();

              final name =
                  data['name']
                          ?.toString() ??
                      'Unknown';

              final latitude =
                  (data['latitude']
                          as num?)
                      ?.toDouble();

              final longitude =
                  (data['longitude']
                          as num?)
                      ?.toDouble();

              return ListTile(
                tileColor:
                    Colors.white,
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    18,
                  ),
                ),
                leading:
                    const CircleAvatar(
                  backgroundColor:
                      Color(0xFFE8F2FF),
                  child: Icon(
                    Icons.location_city,
                    color:
                        Color(0xFF4A90E2),
                  ),
                ),
                title: Text(
                  name,
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                subtitle:
                    const Text(
                  'Tap to view weather',
                ),
                trailing:
                    const Icon(
                  Icons
                      .chevron_right,
                ),
                onTap:
                    latitude == null ||
                            longitude ==
                                null
                        ? null
                        : () async {
                            await onCitySelected(
                              {
                                'name':
                                    name,
                                'latitude':
                                    latitude,
                                'longitude':
                                    longitude,
                              },
                            );

                            if (context
                                .mounted) {
                              Navigator.pop(
                                context,
                              );
                            }
                          },
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// WEATHER INFO
// ============================================================================

class _WeatherInfo
    extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _WeatherInfo({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Expanded(
      child: Column(
        children: [
          Icon(
            icon,
            color: Colors.white,
            size: 22,
          ),
          const SizedBox(
            height: 6,
          ),
          Text(
            label,
            style:
                const TextStyle(
              color:
                  Colors.white70,
              fontSize: 12,
            ),
          ),
          const SizedBox(
            height: 3,
          ),
          Text(
            value,
            style:
                const TextStyle(
              color: Colors.white,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// HOURLY FORECAST CARD
// ============================================================================

class _ForecastCard
    extends StatelessWidget {
  final String time;
  final String temperature;
  final IconData icon;

  const _ForecastCard({
    required this.time,
    required this.temperature,
    required this.icon,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: 95,
      margin:
          const EdgeInsets.only(
        right: 12,
      ),
      padding:
          const EdgeInsets.all(
        14,
      ),
      decoration:
          BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(
          18,
        ),
        boxShadow: const [
          BoxShadow(
            color:
                Colors.black12,
            blurRadius: 8,
            offset:
                Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment
                .spaceAround,
        children: [
          Text(
            time,
            style:
                const TextStyle(
              color: Colors.grey,
              fontSize: 13,
            ),
          ),
          Icon(
            icon,
            color:
                const Color(
              0xFF4A90E2,
            ),
            size: 28,
          ),
          Text(
            temperature,
            style:
                const TextStyle(
              fontSize: 18,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// INSIGHT CARD
// ============================================================================

class _InsightCard
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _InsightCard({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.all(
        18,
      ),
      decoration:
          BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(
          18,
        ),
        boxShadow: const [
          BoxShadow(
            color:
                Colors.black12,
            blurRadius: 8,
            offset:
                Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment
                .start,
        children: [
          Icon(
            icon,
            color:
                const Color(
              0xFF4A90E2,
            ),
            size: 28,
          ),
          const SizedBox(
            height: 12,
          ),
          Text(
            title,
            style:
                const TextStyle(
              color: Colors.grey,
              fontSize: 13,
            ),
          ),
          const SizedBox(
            height: 4,
          ),
          Text(
            value,
            style:
                const TextStyle(
              fontSize: 18,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}