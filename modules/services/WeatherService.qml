pragma Singleton

import QtQuick
import QtQml
import Quickshell

import qs.modules.config
import qs.modules.globals

Singleton {
    id: root

    // Current weather data
    property string weatherSymbol: ""
    property real currentTemp: 0
    property real maxTemp: 0
    property real minTemp: 0
    property int weatherCode: 0
    property real windSpeed: 0
    property bool dataAvailable: false
    property bool isLoading: false
    property bool hasFailed: false

    // 7-day forecast data
    property var forecast: []

    // Sun position data
    property string sunrise: ""  // HH:MM
    property string sunset: ""   // HH:MM
    property real sunProgress: 0.0  // Arc position (0.0-1.0)
    property bool isDay: true
    property string timeOfDay: "Day"  // "Day", "Evening", "Night"
    property string weatherDescription: ""

    // Debug mode
    property bool debugMode: false
    property real debugHour: 12.0  // 0-24 hour (e.g. 14.5 = 2:30 PM)
    property int debugWeatherCode: 0

    // Retry logic
    property int retryCount: 0
    readonly property int maxRetries: 3

    // HTTP request state
    property var activeRequest: null
    property var activeFailureCallback: null
    property int activeRequestGeneration: -1
    property int requestGeneration: 0

    readonly property int requestTimeoutMs: 15000

    property var suspendConnections: Connections {
        target: SuspendManager

        function onPreparingForSleep() {
            root.cancelActiveRequest();

            if (retryTimer)
                retryTimer.stop();

            root.isLoading = false;
        }

        function onWakingUp() {
            if (wakeRefreshTimer)
                wakeRefreshTimer.restart();
        }
    }

    property Timer requestTimeoutTimer: Timer {
        interval: root.requestTimeoutMs
        repeat: false

        onTriggered: {
            var xhr = root.activeRequest;
            var failure = root.activeFailureCallback;
            var generation = root.activeRequestGeneration;

            root.activeRequest = null;
            root.activeFailureCallback = null;
            root.activeRequestGeneration = -1;

            if (xhr) {
                try {
                    xhr.abort();
                } catch (e) {
                    // Request may already have terminated.
                }
            }

            if (generation === root.requestGeneration && failure)
                failure("Request timed out");
        }
    }

    property var wakeRefreshTimer: Timer {
        id: wakeRefreshTimer
        interval: 5000
        repeat: false
        onTriggered: root.updateWeather()
    }

    property Timer refreshTimer: Timer {
        interval: 600000  // 10 minutes
        running: !SuspendManager.isSuspending
        repeat: true
        onTriggered: root.updateWeather()
    }

    property Timer sunPositionTimer: Timer {
        interval: 60000  // 1 minute
        running: !SuspendManager.isSuspending && (GlobalStates.dashboardOpen || GlobalStates.launcherOpen || GlobalStates.overviewOpen)
        repeat: true
        onTriggered: root.calculateSunPosition()
    }

    property Timer retryTimer: Timer {
        interval: 3000
        repeat: false
        onTriggered: root.updateWeather()
    }

    // Convert "HH:MM" to decimal hours
    function parseTime(timeStr) {
        if (!timeStr)
            return 0;
        var parts = timeStr.split(":");
        return parseInt(parts[0]) + parseInt(parts[1]) / 60;
    }

    // Fixed sunrise/sunset for visual consistency (sun at zenith at 12:00)
    readonly property real visualSunriseHour: 6.0
    readonly property real visualSunsetHour: 18.0

    // Calculate sun/moon progress based on hour (0-24 format)
    function calculateSunProgress(hour, sunriseH, sunsetH) {
        if (hour >= sunriseH && hour <= sunsetH) {
            return (hour - sunriseH) / (sunsetH - sunriseH);
        } else {
            var nightDuration = 24 - (sunsetH - sunriseH);
            if (hour > sunsetH) {
                return (hour - sunsetH) / nightDuration;
            } else {
                return (hour + (24 - sunsetH)) / nightDuration;
            }
        }
    }

    // Calculate debug values based on debugHour
    readonly property real debugSunProgress: calculateSunProgress(debugHour, visualSunriseHour, visualSunsetHour)
    readonly property bool debugIsDay: debugHour >= visualSunriseHour && debugHour <= visualSunsetHour

    // Transition scheme for time blending
    function calculateTimeBlend(hour) {
        var day = 0, evening = 0, night = 0;

        if (hour >= 9 && hour <= 17) {
            day = 1.0;
        } else if (hour > 8 && hour < 9) {
            var t = hour - 8;
            evening = 1.0 - t;
            day = t;
        } else if (hour > 17 && hour < 18) {
            var t = hour - 17;
            day = 1.0 - t;
            evening = t;
        } else if (hour >= 6 && hour <= 8) {
            evening = 1.0;
        } else if (hour >= 18 && hour <= 20) {
            evening = 1.0;
        } else if (hour > 5 && hour < 6) {
            var t = hour - 5;
            night = 1.0 - t;
            evening = t;
        } else if (hour > 20 && hour < 21) {
            var t = hour - 20;
            evening = 1.0 - t;
            night = t;
        } else {
            night = 1.0;
        }

        return {
            day: day,
            evening: evening,
            night: night
        };
    }

    readonly property var debugTimeBlend: calculateTimeBlend(debugHour)
    property real currentHour: 12.0
    readonly property var realTimeBlend: calculateTimeBlend(currentHour)
    readonly property real realSunProgress: calculateSunProgress(currentHour, visualSunriseHour, visualSunsetHour)
    readonly property real realSunriseHour: sunrise.length > 0 ? parseTime(sunrise) : 6.0
    readonly property real realSunsetHour: sunset.length > 0 ? parseTime(sunset) : 18.0
    readonly property bool realIsDay: currentHour >= realSunriseHour && currentHour <= realSunsetHour

    readonly property var effectiveTimeBlend: debugMode ? debugTimeBlend : realTimeBlend

    readonly property string debugTimeOfDay: {
        var blend = debugTimeBlend;
        if (blend.day >= blend.evening && blend.day >= blend.night)
            return "Day";
        if (blend.evening >= blend.night)
            return "Evening";
        return "Night";
    }

    // Effective values (use debug values when debugMode is on)
    readonly property real effectiveSunProgress: debugMode ? debugSunProgress : realSunProgress
    readonly property string effectiveTimeOfDay: debugMode ? debugTimeOfDay : timeOfDay
    readonly property bool effectiveIsDay: debugMode ? debugIsDay : realIsDay
    readonly property int effectiveWeatherCode: debugMode ? debugWeatherCode : weatherCode
    readonly property string effectiveWeatherSymbol: debugMode ? getWeatherCodeEmoji(debugWeatherCode) : weatherSymbol
    readonly property string effectiveWeatherDescription: debugMode ? getWeatherDescription(debugWeatherCode) : weatherDescription

    // Weather effect types based on code
    readonly property string effectiveWeatherEffect: getWeatherEffect(effectiveWeatherCode)
    readonly property real effectiveWeatherIntensity: getWeatherIntensity(effectiveWeatherCode)

    function getWeatherEffect(code) {
        if (code === 0 || code === 1)
            return "clear";
        if (code === 2 || code === 3)
            return "clouds";
        if (code === 45 || code === 48)
            return "fog";
        if (code >= 51 && code <= 57)
            return "drizzle";
        if (code >= 61 && code <= 67)
            return "rain";
        if (code >= 71 && code <= 77)
            return "snow";
        if (code >= 80 && code <= 82)
            return "rain";
        if (code >= 85 && code <= 86)
            return "snow";
        if (code === 95)
            return "thunderstorm";
        if (code >= 96 && code <= 99)
            return "thunderstorm";
        return "clear";
    }

    function getWeatherIntensity(code) {
        if (code === 0 || code === 1)
            return 0.0;
        if (code === 2)
            return 0.5;
        if (code === 3)
            return 1.0;
        if (code === 45)
            return 0.5;
        if (code === 48)
            return 0.7;
        if (code === 51 || code === 56)
            return 0.3;
        if (code === 53)
            return 0.5;
        if (code === 55 || code === 57)
            return 0.7;
        if (code === 61)
            return 0.4;
        if (code === 63 || code === 66)
            return 0.6;
        if (code === 65 || code === 67)
            return 0.9;
        if (code === 71)
            return 0.3;
        if (code === 73)
            return 0.5;
        if (code === 75 || code === 77)
            return 0.8;
        if (code === 80)
            return 0.5;
        if (code === 81)
            return 0.7;
        if (code === 82)
            return 1.0;
        if (code === 85)
            return 0.6;
        if (code === 86)
            return 0.9;
        if (code === 95)
            return 0.8;
        if (code >= 96)
            return 1.0;
        return 0.0;
    }

    function getWeatherDescription(code) {
        if (code === 0)
            return "Clear sky";
        if (code === 1)
            return "Mainly clear";
        if (code === 2)
            return "Partly cloudy";
        if (code === 3)
            return "Overcast";
        if (code === 45)
            return "Foggy";
        if (code === 48)
            return "Rime fog";
        if (code >= 51 && code <= 53)
            return "Light drizzle";
        if (code === 55)
            return "Dense drizzle";
        if (code >= 56 && code <= 57)
            return "Freezing drizzle";
        if (code === 61)
            return "Light rain";
        if (code === 63)
            return "Moderate rain";
        if (code === 65)
            return "Heavy rain";
        if (code >= 66 && code <= 67)
            return "Freezing rain";
        if (code === 71)
            return "Light snow";
        if (code === 73)
            return "Moderate snow";
        if (code === 75)
            return "Heavy snow";
        if (code === 77)
            return "Snow grains";
        if (code >= 80 && code <= 81)
            return "Rain showers";
        if (code === 82)
            return "Heavy showers";
        if (code >= 85 && code <= 86)
            return "Snow showers";
        if (code === 95)
            return "Thunderstorm";
        if (code >= 96 && code <= 99)
            return "Thunderstorm with hail";
        return "Unknown";
    }

    function calculateSunPosition() {
        var now = new Date();
        var hour = now.getHours() + now.getMinutes() / 60;

        // Update currentHour so readonly properties can react to time changes
        root.currentHour = hour;

        var sunriseH = sunrise.length > 0 ? parseTime(sunrise) : 6.0;
        var sunsetH = sunset.length > 0 ? parseTime(sunset) : 18.0;

        root.isDay = (hour >= sunriseH && hour <= sunsetH);
        root.sunProgress = calculateSunProgress(hour, sunriseH, sunsetH);

        var blend = calculateTimeBlend(hour);
        if (blend.day >= blend.evening && blend.day >= blend.night) {
            root.timeOfDay = "Day";
        } else if (blend.evening >= blend.night) {
            root.timeOfDay = "Evening";
        } else {
            root.timeOfDay = "Night";
        }
    }

    function getWeatherCodeEmoji(code) {
        if (code === 0)
            return "☀️";
        if (code === 1)
            return "🌤️";
        if (code === 2)
            return "⛅";
        if (code === 3)
            return "☁️";
        if (code === 45)
            return "🌫️";
        if (code === 48)
            return "🌨️";
        if (code >= 51 && code <= 53)
            return "🌦️";
        if (code === 55)
            return "🌧️";
        if (code >= 56 && code <= 57)
            return "🧊";
        if (code >= 61 && code <= 65)
            return "🌧️";
        if (code >= 66 && code <= 67)
            return "🧊";
        if (code >= 71 && code <= 77)
            return "❄️";
        if (code >= 80 && code <= 81)
            return "🌦️";
        if (code === 82)
            return "🌧️";
        if (code >= 85 && code <= 86)
            return "🌨️";
        if (code === 95)
            return "⛈️";
        if (code >= 96 && code <= 99)
            return "🌩️";
        return "❓";
    }

    function convertTemp(temp) {
        if (Config.weather.unit === "F") {
            return (temp * 9 / 5) + 32;
        }
        return temp;
    }

    function handleError() {
        if (retryCount < maxRetries) {
            retryCount++;
            retryTimer.start();
        } else {
            root.isLoading = false;
            root.hasFailed = true;
            retryCount = 0;
        }
    }

    function cancelActiveRequest() {
        // Invalidates callbacks from all requests belonging to the old update.
        root.requestGeneration++;

        requestTimeoutTimer.stop();

        var xhr = root.activeRequest;

        root.activeRequest = null;
        root.activeFailureCallback = null;
        root.activeRequestGeneration = -1;

        if (xhr) {
            try {
                xhr.abort();
            } catch (e) {
                // The request may have already completed.
            }
        }
    }

    function httpGetJson(url, generation, onSuccess, onFailure) {
        if (generation !== root.requestGeneration)
            return;

        var xhr = new XMLHttpRequest();

        root.activeRequest = xhr;
        root.activeFailureCallback = onFailure;
        root.activeRequestGeneration = generation;

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;

            // Ignore stale requests.
            if (generation !== root.requestGeneration)
                return;

            // If this is no longer the active request, it was cancelled or timed out.
            if (root.activeRequest !== xhr)
                return;

            requestTimeoutTimer.stop();

            root.activeRequest = null;
            root.activeFailureCallback = null;
            root.activeRequestGeneration = -1;

            if (xhr.status < 200 || xhr.status >= 300) {
                var errorMessage = "HTTP request failed with status " + xhr.status;

                // Open-Meteo returns useful JSON errors for invalid requests.
                if (xhr.responseText) {
                    try {
                        var errorData = JSON.parse(xhr.responseText);

                        if (errorData.reason)
                            errorMessage = errorData.reason;
                        else if (errorData.error && typeof errorData.error === "string")
                            errorMessage = errorData.error;
                    } catch (e) {
                        // Keep the generic HTTP error.
                    }
                }

                onFailure(errorMessage);
                return;
            }

            if (!xhr.responseText || xhr.responseText.trim().length === 0) {
                onFailure("Empty HTTP response");
                return;
            }

            try {
                var data = JSON.parse(xhr.responseText);
                onSuccess(data);
            } catch (e) {
                onFailure("Invalid JSON response: " + e);
            }
        };

        try {
            xhr.open("GET", url, true);
            xhr.setRequestHeader("Accept", "application/json");

            requestTimeoutTimer.restart();
            xhr.send();
        } catch (e) {
            requestTimeoutTimer.stop();

            if (root.activeRequest === xhr) {
                root.activeRequest = null;
                root.activeFailureCallback = null;
                root.activeRequestGeneration = -1;
            }

            onFailure("Could not start HTTP request: " + e);
        }
    }

    function requestFailed(message, generation) {
        if (generation !== root.requestGeneration)
            return;

        console.warn("WeatherService:", message);

        root.dataAvailable = false;
        root.handleError();
    }

    function parseCoordinates(location) {
        // Supports:
        //   40.7128,-74.0060
        //   40.7128, -74.0060
        //   -33.8688,151.2093
        var match = location.match(
            /^\s*(-?(?:\d+(?:\.\d*)?|\.\d+))\s*,\s*(-?(?:\d+(?:\.\d*)?|\.\d+))\s*$/
        );

        if (!match)
            return null;

        var latitude = parseFloat(match[1]);
        var longitude = parseFloat(match[2]);

        if (!isFinite(latitude) || !isFinite(longitude))
            return null;

        if (latitude < -90 || latitude > 90)
            return null;

        if (longitude < -180 || longitude > 180)
            return null;

        return {
            latitude: latitude,
            longitude: longitude
        };
    }

    function fetchGeoIp(generation) {
        console.log("WeatherService: Resolving location using GeoIP");

        httpGetJson(
            "https://ipapi.co/json/",
            generation,

            function(data) {
                if (generation !== root.requestGeneration)
                    return;

                var latitude = parseFloat(data.latitude);
                var longitude = parseFloat(data.longitude);

                if (!isFinite(latitude) || !isFinite(longitude)) {
                    root.requestFailed(
                        "Could not determine location from GeoIP",
                        generation
                    );
                    return;
                }

                root.fetchWeatherAtCoordinates(
                    latitude,
                    longitude,
                    generation
                );
            },

            function(error) {
                root.requestFailed(
                    "GeoIP request failed: " + error,
                    generation
                );
            }
        );
    }

    function geocodeLocation(location, generation) {
        console.log("WeatherService: Geocoding '" + location + "'");

        var url =
            "https://geocoding-api.open-meteo.com/v1/search" +
            "?name=" + encodeURIComponent(location) +
            "&count=1" +
            "&format=json";

        httpGetJson(
            url,
            generation,

            function(data) {
                if (generation !== root.requestGeneration)
                    return;

                if (!data.results || data.results.length === 0) {
                    root.requestFailed(
                        "Location not found: " + location,
                        generation
                    );
                    return;
                }

                var result = data.results[0];

                var latitude = parseFloat(result.latitude);
                var longitude = parseFloat(result.longitude);

                if (!isFinite(latitude) || !isFinite(longitude)) {
                    root.requestFailed(
                        "Invalid coordinates returned for location: " + location,
                        generation
                    );
                    return;
                }

                root.fetchWeatherAtCoordinates(
                    latitude,
                    longitude,
                    generation
                );
            },

            function(error) {
                root.requestFailed(
                    "Geocoding request failed: " + error,
                    generation
                );
            }
        );
    }

    function fetchWeatherAtCoordinates(latitude, longitude, generation) {
        if (generation !== root.requestGeneration)
            return;

        console.log(
            "WeatherService: Fetching weather for "
            + latitude + "," + longitude
        );

        var url =
            "https://api.open-meteo.com/v1/forecast" +
            "?latitude=" + encodeURIComponent(latitude) +
            "&longitude=" + encodeURIComponent(longitude) +
            "&current=temperature_2m,weather_code,wind_speed_10m" +
            "&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset,weather_code" +
            "&timezone=auto" +
            "&forecast_days=7";

        httpGetJson(
            url,
            generation,

            function(data) {
                root.processWeatherData(data, generation);
            },

            function(error) {
                root.requestFailed(
                    "Weather API request failed: " + error,
                    generation
                );
            }
        );
    }

    function processWeatherData(data, generation) {
        if (generation !== root.requestGeneration)
            return;

        if (!data.current || !data.daily) {
            root.requestFailed(
                "Invalid weather API response",
                generation
            );
            return;
        }

        var weather = data.current;
        var daily = data.daily;

        var currentTemperature = parseFloat(weather.temperature_2m);
        var currentWeatherCode = parseInt(weather.weather_code);
        var currentWindSpeed = parseFloat(weather.wind_speed_10m);

        if (isNaN(currentTemperature) || isNaN(currentWeatherCode)) {
            root.requestFailed(
                "Current weather data is incomplete",
                generation
            );
            return;
        }

        root.weatherCode = currentWeatherCode;
        root.currentTemp = root.convertTemp(currentTemperature);
        root.windSpeed = isNaN(currentWindSpeed) ? 0 : currentWindSpeed;

        if (daily.temperature_2m_max &&
            daily.temperature_2m_max.length > 0) {
            root.maxTemp = root.convertTemp(
                parseFloat(daily.temperature_2m_max[0])
            );
        }

        if (daily.temperature_2m_min &&
            daily.temperature_2m_min.length > 0) {
            root.minTemp = root.convertTemp(
                parseFloat(daily.temperature_2m_min[0])
            );
        }

        if (daily.sunrise && daily.sunrise.length > 0) {
            var sunriseParts = daily.sunrise[0].split("T");
            root.sunrise = sunriseParts.length > 1
                ? sunriseParts[1]
                : "";
        }

        if (daily.sunset && daily.sunset.length > 0) {
            var sunsetParts = daily.sunset[0].split("T");
            root.sunset = sunsetParts.length > 1
                ? sunsetParts[1]
                : "";
        }

        // Parse 7-day forecast
        var forecastData = [];
        var dayCount = Math.min(
            7,
            daily.time ? daily.time.length : 0
        );

        for (var i = 0; i < dayCount; i++) {
            // Parse YYYY-MM-DD manually so the date is interpreted
            // in local time instead of as UTC midnight.
            var dateParts = daily.time[i].split("-");

            var year = parseInt(dateParts[0]);
            var month = parseInt(dateParts[1]) - 1;
            var day = parseInt(dateParts[2]);

            var dayDate = new Date(year, month, day);

            var rawDayName = i === 0
                ? "Today"
                : dayDate.toLocaleDateString(Qt.locale(), "ddd");

            var dayName =
                rawDayName.charAt(0).toUpperCase()
                + rawDayName.slice(1);

            var forecastWeatherCode =
                daily.weather_code &&
                daily.weather_code[i] !== undefined
                    ? parseInt(daily.weather_code[i])
                    : 0;

            var dayMax =
                daily.temperature_2m_max &&
                daily.temperature_2m_max[i] !== undefined
                    ? parseFloat(daily.temperature_2m_max[i])
                    : 0;

            var dayMin =
                daily.temperature_2m_min &&
                daily.temperature_2m_min[i] !== undefined
                    ? parseFloat(daily.temperature_2m_min[i])
                    : 0;

            forecastData.push({
                date: daily.time[i],
                dayName: dayName,
                weatherCode: forecastWeatherCode,
                emoji: root.getWeatherCodeEmoji(forecastWeatherCode),
                maxTemp: root.convertTemp(dayMax),
                minTemp: root.convertTemp(dayMin)
            });
        }

        root.forecast = forecastData;

        root.weatherSymbol = root.getWeatherCodeEmoji(root.weatherCode);
        root.weatherDescription =
            root.getWeatherDescription(root.weatherCode);

        root.calculateSunPosition();

        root.dataAvailable = true;
        root.isLoading = false;
        root.hasFailed = false;
        root.retryCount = 0;
    }

    // Watch for config changes
    property var weatherConfig: Config.weather
    readonly property string configLocation: weatherConfig ? weatherConfig.location : ""
    readonly property string configUnit: weatherConfig ? weatherConfig.unit : "C"
    property bool _initialized: false

    function updateWeather() {
        // Stop any previous request and invalidate its callbacks.
        root.cancelActiveRequest();

        if (!Config.weather) {
            console.warn("WeatherService: Config.weather is null");
            root.isLoading = false;
            return;
        }

        root.isLoading = true;
        root.hasFailed = false;

        var locationStr = Config.weather.location || "";
        var location = locationStr.trim();

        // cancelActiveRequest() advanced the generation.
        var generation = root.requestGeneration;

        console.log(
            "WeatherService: Fetching weather for '" + location + "'"
        );

        // Empty location means automatic GeoIP location.
        if (location.length === 0) {
            root.fetchGeoIp(generation);
            return;
        }

        // Explicit latitude/longitude.
        var coordinates = root.parseCoordinates(location);

        if (coordinates) {
            root.fetchWeatherAtCoordinates(
                coordinates.latitude,
                coordinates.longitude,
                generation
            );
            return;
        }

        // Otherwise treat the value as a city/location name.
        root.geocodeLocation(location, generation);
    }

    Timer {
        id: startupDelay
        interval: 2000
        running: true
        onTriggered: updateWeather()
    }

    Component.onCompleted: {
        var now = new Date();
        currentHour = now.getHours() + now.getMinutes() / 60;
        _initialized = true;
    }

    onConfigLocationChanged: {
        if (!_initialized)
            return;

        console.log(
            "WeatherService: Location changed to '" +
            configLocation + "'"
        );

        retryTimer.stop();
        retryCount = 0;

        Qt.callLater(function() {
            root.updateWeather();
        });
    }

    onConfigUnitChanged: {
        if (!_initialized)
            return;

        console.log(
            "WeatherService: Unit changed to '" +
            configUnit + "'"
        );

        retryTimer.stop();
        retryCount = 0;

        Qt.callLater(function() {
            root.updateWeather();
        });
    }
}
