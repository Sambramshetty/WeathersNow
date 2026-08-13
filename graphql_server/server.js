const { ApolloServer } = require('@apollo/server');
const { startStandaloneServer } = require('@apollo/server/standalone');

const typeDefs = `#graphql
  type CurrentWeather {
    temperature: Float
    humidity: Int
    apparentTemperature: Float
    precipitation: Float
    weatherCode: Int
    windSpeed: Float
    visibility: Float
    isDay: Boolean
  }

  type HourlyWeather {
    time: String
    temperature: Float
    weatherCode: Int
  }

  type DailyWeather {
    date: String
    weatherCode: Int
    temperatureMax: Float
    temperatureMin: Float
    precipitationProbability: Int
    uvIndex: Float
  }

  type Weather {
    current: CurrentWeather
    hourly: [HourlyWeather]
    daily: [DailyWeather]
  }

  type City {
    name: String
    latitude: Float
    longitude: Float
    country: String
    countryCode: String
    state: String
    population: Int
    featureCode: String
  }

  type Query {
    weather(latitude: Float!, longitude: Float!): Weather
    searchCity(city: String!): [City]
  }
`;

const resolvers = {
  Query: {
    // ============================================================
    // WEATHER
    // ============================================================

    weather: async (_, { latitude, longitude }) => {
      const url =
        `https://api.open-meteo.com/v1/forecast` +
        `?latitude=${latitude}` +
        `&longitude=${longitude}` +
        `&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,wind_speed_10m,visibility` +
        `&hourly=temperature_2m,weather_code` +
        `&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,uv_index_max` +
        `&timezone=auto`;

      const response = await fetch(url);

      if (!response.ok) {
        throw new Error(`Weather API error: ${response.status}`);
      }

      const data = await response.json();
      const current = data.current;

      // ----------------------------------------------------------
      // HOURLY
      // ----------------------------------------------------------

      const hourly = [];

      if (data.hourly?.time) {
        for (let i = 0; i < data.hourly.time.length; i++) {
          hourly.push({
            time: data.hourly.time[i],
            temperature: data.hourly.temperature_2m?.[i],
            weatherCode: data.hourly.weather_code?.[i],
          });
        }
      }

      // ----------------------------------------------------------
      // DAILY
      // ----------------------------------------------------------

      const daily = [];

      if (data.daily?.time) {
        for (let i = 0; i < data.daily.time.length; i++) {
          daily.push({
            date: data.daily.time[i],
            weatherCode: data.daily.weather_code?.[i],
            temperatureMax: data.daily.temperature_2m_max?.[i],
            temperatureMin: data.daily.temperature_2m_min?.[i],
            precipitationProbability:
              data.daily.precipitation_probability_max?.[i],
            uvIndex: data.daily.uv_index_max?.[i],
          });
        }
      }

      return {
        current: {
          temperature: current?.temperature_2m,
          humidity: current?.relative_humidity_2m,
          apparentTemperature: current?.apparent_temperature,
          precipitation: current?.precipitation,
          weatherCode: current?.weather_code,
          windSpeed: current?.wind_speed_10m,
          visibility: current?.visibility,
          isDay: current?.is_day === 1,
        },
        hourly,
        daily,
      };
    },

    // ============================================================
    // CITY SEARCH
    // ============================================================

    searchCity: async (_, { city }) => {
      const originalQuery = city.trim();

      if (originalQuery.length === 0) {
        return [];
      }

      const normalizedQuery = originalQuery.toLowerCase();

      let searchName = originalQuery;

      // Common Indian city aliases
      if (normalizedQuery === 'bangalore') {
        searchName = 'Bengaluru';
      } else if (normalizedQuery === 'bombay') {
        searchName = 'Mumbai';
      } else if (normalizedQuery === 'calcutta') {
        searchName = 'Kolkata';
      } else if (normalizedQuery === 'madras') {
        searchName = 'Chennai';
      } else if (normalizedQuery === 'poona') {
        searchName = 'Pune';
      }

      const query = encodeURIComponent(searchName);

      const url =
        `https://geocoding-api.open-meteo.com/v1/search` +
        `?name=${query}` +
        `&count=20` +
        `&language=en` +
        `&format=json` +
        `&countryCode=IN`;

      const response = await fetch(url);

      if (!response.ok) {
        throw new Error(
          `Geocoding API error: ${response.status}`
        );
      }

      const data = await response.json();

      if (!data.results) {
        return [];
      }

      // Only Indian results
      const indianResults = data.results.filter((result) => {
        return result.country_code?.toString().toUpperCase() === 'IN';
      });

      // ----------------------------------------------------------
      // RELEVANCE SCORING
      // ----------------------------------------------------------

      function scoreResult(result) {
        const name =
          result.name?.toString().toLowerCase() ?? '';

        const featureCode =
          result.feature_code?.toString().toUpperCase() ?? '';

        const population =
          Number.isFinite(result.population)
            ? result.population
            : 0;

        let score = 0;

        // Exact match
        if (name === normalizedQuery) {
          score += 1000;
        }

        // Bangalore → Bengaluru
        if (
          normalizedQuery === 'bangalore' &&
          name === 'bengaluru'
        ) {
          score += 2000;
        }

        if (
          normalizedQuery === 'bengaluru' &&
          name === 'bengaluru'
        ) {
          score += 2000;
        }

        // Starts with search text
        if (name.startsWith(normalizedQuery)) {
          score += 500;
        }

        // Contains search text
        if (name.includes(normalizedQuery)) {
          score += 100;
        }

        // Prefer cities
        if (featureCode === 'PPLA') {
          score += 300;
        }

        if (featureCode === 'PPLC') {
          score += 500;
        }

        if (featureCode === 'PPL') {
          score += 50;
        }

        // Population
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

      indianResults.sort((a, b) => {
        return scoreResult(b) - scoreResult(a);
      });

      // Return top 5
      return indianResults.slice(0, 5).map((result) => ({
        name: result.name,
        latitude: result.latitude,
        longitude: result.longitude,
        country: result.country,
        countryCode: result.country_code,
        state: result.admin1,
        population: result.population,
        featureCode: result.feature_code,
      }));
    },
  },
};

const server = new ApolloServer({
  typeDefs,
  resolvers,
});

startStandaloneServer(server, {
  listen: {
    port: 4000,
  },
}).then(({ url }) => {
  console.log(`GraphQL server running at ${url}`);
});