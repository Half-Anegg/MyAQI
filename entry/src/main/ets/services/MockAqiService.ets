import { AqiSnapshot, PollutantVector } from '../models/AqiModels';
import { getQualityLabel } from './PlantAlgorithm';
import { AqiClient } from './AqiClient';

export class MockAqiService {
  private cityClient: AqiClient = new AqiClient();

  createSnapshot(cityInput: string, dayOffset: number, profile: string): AqiSnapshot {
    const cityName = this.cityClient.normalizeCityName(cityInput.length === 0 ? '测试市' : cityInput);
    const pollutants = this.createPollutants(dayOffset, profile);
    const aqi = this.estimateAqi(pollutants);
    return {
      cityKey: this.makeCityKey(cityName),
      cityName,
      stationName: `${cityName}模拟站`,
      aqi,
      qualityLabel: getQualityLabel(aqi),
      dominantPollutant: this.getDominantPollutant(pollutants),
      observedAt: this.makeObservedAt(dayOffset),
      sourceName: '模拟数据',
      sourceUrl: 'local://mock-aqi',
      pollutants,
      missingPollutants: []
    };
  }

  private createPollutants(dayOffset: number, profile: string): PollutantVector {
    const wave = dayOffset % 3;
    if (profile === 'polluted') {
      return {
        pm25: 155 + wave * 18,
        pm10: 132 + wave * 15,
        o3: 112 + wave * 10,
        no2: 88 + wave * 8,
        so2: 32 + wave * 5,
        co: 18 + wave * 2
      };
    }
    if (profile === 'pm25') {
      return {
        pm25: 185 + wave * 20,
        pm10: 82 + wave * 8,
        o3: 48 + wave * 6,
        no2: 42 + wave * 6,
        so2: 14 + wave * 3,
        co: 8 + wave
      };
    }
    return {
      pm25: 18 + wave * 4,
      pm10: 26 + wave * 5,
      o3: 32 + wave * 5,
      no2: 18 + wave * 3,
      so2: 6 + wave,
      co: 3 + wave
    };
  }

  private estimateAqi(pollutants: PollutantVector): number {
    const values: number[] = [
      pollutants.pm25 === null ? 0 : pollutants.pm25,
      pollutants.pm10 === null ? 0 : pollutants.pm10,
      pollutants.o3 === null ? 0 : pollutants.o3,
      pollutants.no2 === null ? 0 : pollutants.no2,
      pollutants.so2 === null ? 0 : pollutants.so2,
      pollutants.co === null ? 0 : pollutants.co
    ];
    let max = 0;
    for (let i = 0; i < values.length; i++) {
      if (values[i] > max) {
        max = values[i];
      }
    }
    return Math.round(max);
  }

  private getDominantPollutant(pollutants: PollutantVector): string {
    let dominant = 'pm25';
    let max = pollutants.pm25 === null ? 0 : pollutants.pm25;
    const pm10 = pollutants.pm10 === null ? 0 : pollutants.pm10;
    const o3 = pollutants.o3 === null ? 0 : pollutants.o3;
    const no2 = pollutants.no2 === null ? 0 : pollutants.no2;
    const so2 = pollutants.so2 === null ? 0 : pollutants.so2;
    const co = pollutants.co === null ? 0 : pollutants.co;
    if (pm10 > max) {
      dominant = 'pm10';
      max = pm10;
    }
    if (o3 > max) {
      dominant = 'o3';
      max = o3;
    }
    if (no2 > max) {
      dominant = 'no2';
      max = no2;
    }
    if (so2 > max) {
      dominant = 'so2';
      max = so2;
    }
    if (co > max) {
      dominant = 'co';
    }
    return dominant;
  }

  private makeObservedAt(dayOffset: number): string {
    const base = new Date('2026-05-01T08:00:00+08:00');
    base.setDate(base.getDate() + dayOffset);
    return base.toISOString();
  }

  private makeCityKey(cityName: string): string {
    return cityName.trim().toLowerCase().replace(/\s+/g, '_');
  }
}
