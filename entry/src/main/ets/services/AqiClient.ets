import { http } from '@kit.NetworkKit';
import { AQI_WAQI_TOKEN, HAS_WAQI_TOKEN } from '../config/ApiConfig';
import { AqiSnapshot, PollutantVector, createEmptyPollutants } from '../models/AqiModels';
import { getQualityLabel } from './PlantAlgorithm';

export interface WaqiIaqiItem {
  v?: number | string;
}

export interface WaqiIaqi {
  pm25?: WaqiIaqiItem;
  pm10?: WaqiIaqiItem;
  o3?: WaqiIaqiItem;
  no2?: WaqiIaqiItem;
  so2?: WaqiIaqiItem;
  co?: WaqiIaqiItem;
}

export interface WaqiCity {
  name?: string;
  url?: string;
}

export interface WaqiTime {
  s?: string;
  iso?: string;
}

export interface WaqiData {
  aqi?: number | string;
  idx?: number;
  city?: WaqiCity;
  iaqi?: WaqiIaqi;
  time?: WaqiTime;
  dominentpol?: string;
}

export interface WaqiResponse {
  status?: string;
  data?: WaqiData | string;
}

export class AqiClient {
  hasToken(): boolean {
    return HAS_WAQI_TOKEN;
  }

  async fetchByCity(city: string): Promise<AqiSnapshot> {
    const normalizedCity = this.normalizeCityName(city.trim());
    if (normalizedCity.length === 0) {
      throw new Error('请输入城市名称');
    }
    const url =
      `https://api.waqi.info/feed/${encodeURIComponent(normalizedCity)}/?token=${AQI_WAQI_TOKEN}&_=${Date.now()}`;
    return this.requestSnapshot(url, normalizedCity);
  }

  async fetchByGeo(latitude: number, longitude: number): Promise<AqiSnapshot> {
    const url = `https://api.waqi.info/feed/geo:${latitude};${longitude}/?token=${AQI_WAQI_TOKEN}&_=${Date.now()}`;
    const geoSnapshot = await this.requestSnapshot(url, '当前位置');
    const cityName = this.normalizeCityName(geoSnapshot.cityName);
    if (cityName.length === 0 || cityName === '当前位置') {
      return geoSnapshot;
    }
    try {
      return await this.fetchByCity(cityName);
    } catch (error) {
      return this.withCityLevelName(geoSnapshot, cityName);
    }
  }

  private async requestSnapshot(url: string, fallbackCityName: string): Promise<AqiSnapshot> {
    if (!HAS_WAQI_TOKEN) {
      throw new Error('请先在 ApiConfig.ets 中配置 WAQI token');
    }

    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 15000
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`网络请求失败：${response.responseCode}`);
      }
      const body = response.result as string;
      const parsed = JSON.parse(body) as WaqiResponse;
      return this.parseResponse(parsed, fallbackCityName);
    } catch (error) {
      if (error instanceof Error && error.message.length > 0) {
        throw error;
      }
      throw new Error('暂时无法连接 WAQI 数据服务');
    } finally {
      request.destroy();
    }
  }

  parseResponse(response: WaqiResponse, fallbackCityName: string): AqiSnapshot {
    if (response.status !== 'ok') {
      const message = typeof response.data === 'string' ? response.data : 'WAQI 返回异常';
      throw new Error(message);
    }
    if (typeof response.data !== 'object' || response.data === null) {
      throw new Error('WAQI 数据为空');
    }

    const data = response.data as WaqiData;
    const pollutants = createEmptyPollutants();
    pollutants.pm25 = this.readIaqiValue(data.iaqi?.pm25);
    pollutants.pm10 = this.readIaqiValue(data.iaqi?.pm10);
    pollutants.o3 = this.readIaqiValue(data.iaqi?.o3);
    pollutants.no2 = this.readIaqiValue(data.iaqi?.no2);
    pollutants.so2 = this.readIaqiValue(data.iaqi?.so2);
    pollutants.co = this.readIaqiValue(data.iaqi?.co);

    const stationName = this.cleanDisplayName(data.city?.name, fallbackCityName);
    const cityName = this.normalizeCityName(stationName);
    const stationUrl = data.city?.url ?? 'https://aqicn.org/';
    const aqi = this.toNumberOrNull(data.aqi);
    const missingPollutants = this.collectMissingPollutants(pollutants);

    return {
      cityKey: this.makeCityKey(cityName),
      cityName,
      stationName,
      aqi,
      qualityLabel: getQualityLabel(aqi),
      dominantPollutant: data.dominentpol ?? '暂无',
      observedAt: data.time?.iso ?? data.time?.s ?? '',
      sourceName: 'WAQI',
      sourceUrl: stationUrl,
      pollutants,
      missingPollutants
    };
  }

  private readIaqiValue(item: WaqiIaqiItem | undefined): number | null {
    if (item === undefined) {
      return null;
    }
    return this.toNumberOrNull(item.v);
  }

  private toNumberOrNull(value: number | string | undefined): number | null {
    if (value === undefined) {
      return null;
    }
    if (typeof value === 'number') {
      return isNaN(value) ? null : value;
    }
    const parsed = Number(value);
    return isNaN(parsed) ? null : parsed;
  }

  private collectMissingPollutants(pollutants: PollutantVector): string[] {
    const missing: string[] = [];
    if (pollutants.pm25 === null) {
      missing.push('PM2.5');
    }
    if (pollutants.pm10 === null) {
      missing.push('PM10');
    }
    if (pollutants.o3 === null) {
      missing.push('O3');
    }
    if (pollutants.no2 === null) {
      missing.push('NO2');
    }
    if (pollutants.so2 === null) {
      missing.push('SO2');
    }
    if (pollutants.co === null) {
      missing.push('CO');
    }
    return missing;
  }

  normalizeCityName(name: string): string {
    const raw = this.cleanDisplayName(name, name);
    const segments = raw.split(/[,，、()（）/]/).map((item: string) => item.trim())
      .filter((item: string) => item.length > 0 && item !== 'China' && item !== '中国');
    for (let i = 0; i < segments.length; i++) {
      const city = this.extractChineseCityName(segments[i]);
      if (city.length > 0) {
        return city;
      }
    }
    const directCity = this.extractChineseCityName(raw);
    if (directCity.length > 0) {
      return directCity;
    }
    if (segments.length > 1) {
      return segments[segments.length - 1];
    }
    return raw.trim();
  }

  private extractChineseCityName(text: string): string {
    const cityMatch = text.match(/[\u4e00-\u9fa5]{2,12}市/);
    if (cityMatch !== null && cityMatch.length > 0) {
      return cityMatch[0];
    }

    const municipalities: string[] = ['北京', '上海', '天津', '重庆'];
    for (let i = 0; i < municipalities.length; i++) {
      if (text.indexOf(municipalities[i]) >= 0) {
        return `${municipalities[i]}市`;
      }
    }

    const chineseMatches = text.match(/[\u4e00-\u9fa5]+/g);
    if (chineseMatches === null || chineseMatches.length === 0) {
      return '';
    }
    const chineseText = chineseMatches.join('');
    if (chineseText.length >= 2 && chineseText.length <= 6 &&
      chineseText.indexOf('省') < 0 &&
      chineseText.indexOf('区') < 0 &&
      chineseText.indexOf('县') < 0 &&
      chineseText.indexOf('镇') < 0 &&
      chineseText.indexOf('街') < 0) {
      if (chineseText === '香港' || chineseText === '澳门') {
        return chineseText;
      }
      return `${chineseText}市`;
    }
    return '';
  }

  private cleanDisplayName(name: string | undefined, fallback: string): string {
    const raw = name === undefined || name.trim().length === 0 ? fallback : name;
    return raw.replace(', China', '').replace('China', '').replace('中国', '').trim();
  }

  private makeCityKey(cityName: string): string {
    return this.normalizeCityName(cityName).trim().toLowerCase().replace(/\s+/g, '_');
  }

  private withCityLevelName(snapshot: AqiSnapshot, cityName: string): AqiSnapshot {
    return {
      cityKey: this.makeCityKey(cityName),
      cityName,
      stationName: snapshot.stationName,
      aqi: snapshot.aqi,
      qualityLabel: snapshot.qualityLabel,
      dominantPollutant: snapshot.dominantPollutant,
      observedAt: snapshot.observedAt,
      sourceName: snapshot.sourceName,
      sourceUrl: snapshot.sourceUrl,
      pollutants: snapshot.pollutants,
      missingPollutants: snapshot.missingPollutants
    };
  }
}
