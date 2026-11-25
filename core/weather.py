#!/usr/bin/env python3
"""Fetch current weather + today's high/low + air quality from Open-Meteo (no API key).

Uses the same location as the sky (living-sky.conf / cached IP geolocation) and writes
  ~/.cache/living-sky/weather.lua   flat Lua table read by the theme Lua
  ~/.cache/living-sky/weather.json  raw-ish summary read by sky.py (clouds / rain in the wallpaper)
On any network error the previous files are left untouched (stale data is shown dimmed).
"""
import json, os, subprocess, sys, time, urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sky  # noqa: E402  (location + cache paths)

def get(url, params):
    q = url + '?' + urllib.parse.urlencode(params)
    out = subprocess.run(['curl', '-fsS', '-m', '8', '-A', 'living-sky', q],
                         capture_output=True, text=True, timeout=12)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip())
    return json.loads(out.stdout)

# WMO weather code -> (text, kind); kind picks the icon / wallpaper effect
WMO = {
    0: ('Clear', 'clear'), 1: ('Mostly clear', 'clear'), 2: ('Partly cloudy', 'partly'), 3: ('Overcast', 'cloudy'),
    45: ('Fog', 'fog'), 48: ('Rime fog', 'fog'),
    51: ('Light drizzle', 'rain'), 53: ('Drizzle', 'rain'), 55: ('Heavy drizzle', 'rain'),
    56: ('Freezing drizzle', 'sleet'), 57: ('Freezing drizzle', 'sleet'),
    61: ('Light rain', 'rain'), 63: ('Rain', 'rain'), 65: ('Heavy rain', 'pour'),
    66: ('Freezing rain', 'sleet'), 67: ('Freezing rain', 'sleet'),
    71: ('Light snow', 'snow'), 73: ('Snow', 'snow'), 75: ('Heavy snow', 'snow'), 77: ('Snow grains', 'snow'),
    80: ('Rain showers', 'rain'), 81: ('Rain showers', 'rain'), 82: ('Violent showers', 'pour'),
    85: ('Snow showers', 'snow'), 86: ('Snow showers', 'snow'),
    95: ('Thunderstorm', 'storm'), 96: ('Storm, hail', 'storm'), 99: ('Storm, hail', 'storm'),
}

def lua_value(v):
    if isinstance(v, str): return json.dumps(v)
    if isinstance(v, bool): return 'true' if v else 'false'
    if isinstance(v, (int, float)): return repr(round(v, 1)) if isinstance(v, float) else str(v)
    if isinstance(v, list): return '{' + ', '.join(lua_value(x) for x in v) + '}'
    if isinstance(v, dict): return '{' + ', '.join('%s = %s' % (k, lua_value(x)) for k, x in v.items()) + '}'
    return 'nil'

def main():
    lat, lon, name = sky.get_location(sky.read_conf())
    f = get('https://api.open-meteo.com/v1/forecast', {
        'latitude': round(lat, 2), 'longitude': round(lon, 2), 'timezone': 'auto', 'forecast_days': 1,
        'current': 'temperature_2m,apparent_temperature,relative_humidity_2m,is_day,weather_code,'
                   'cloud_cover,wind_speed_10m,wind_direction_10m,precipitation,uv_index',
        'daily': 'temperature_2m_max,temperature_2m_min,uv_index_max,precipitation_probability_max',
    })
    aqi = None
    try:
        a = get('https://air-quality-api.open-meteo.com/v1/air-quality', {
            'latitude': round(lat, 2), 'longitude': round(lon, 2), 'timezone': 'auto', 'current': 'us_aqi,pm2_5'})
        aqi = a['current'].get('us_aqi')
    except Exception:
        pass
    c, d = f['current'], f['daily']
    text, kind = WMO.get(c['weather_code'], ('—', 'cloudy'))
    w = {
        'ok': True, 'fetched': int(time.time()), 'place': name or '',
        'temp': c['temperature_2m'], 'feels': c['apparent_temperature'], 'hum': c['relative_humidity_2m'],
        'day': bool(c['is_day']), 'code': c['weather_code'], 'text': text, 'kind': kind,
        'cloud': c['cloud_cover'], 'wind': c['wind_speed_10m'], 'wdir': c['wind_direction_10m'],
        'precip': c.get('precipitation') or 0,
        'hi': d['temperature_2m_max'][0], 'lo': d['temperature_2m_min'][0],
        'uv': d['uv_index_max'][0] or 0, 'uvnow': c.get('uv_index') or 0, 'pop': d['precipitation_probability_max'][0] or 0,
        'aqi': aqi if aqi is not None else -1,
    }
    os.makedirs(sky.CACHE, exist_ok=True)
    for ext, body in (('.lua', 'return ' + lua_value(w) + '\n'), ('.json', json.dumps(w))):
        p = os.path.join(sky.CACHE, 'weather' + ext)
        with open(p + '.tmp', 'w') as fh:
            fh.write(body)
        os.replace(p + '.tmp', p)
    print(name, text, c['temperature_2m'], 'aqi', aqi)

if __name__ == '__main__':
    try:
        main()
    except Exception as ex:   # keep stale data; just log
        print('weather fetch failed:', ex, file=sys.stderr)
        sys.exit(1)
