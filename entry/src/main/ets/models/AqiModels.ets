export type PollutantKey = 'pm25' | 'pm10' | 'o3' | 'no2' | 'so2' | 'co';

export const POLLUTANT_KEYS: PollutantKey[] = ['pm25', 'pm10', 'o3', 'no2', 'so2', 'co'];

export interface PollutantVector {
  pm25: number | null;
  pm10: number | null;
  o3: number | null;
  no2: number | null;
  so2: number | null;
  co: number | null;
}

export interface PlantMemory {
  pm25: number;
  pm10: number;
  o3: number;
  no2: number;
  so2: number;
  co: number;
}

export interface AqiSnapshot {
  cityKey: string;
  cityName: string;
  stationName: string;
  aqi: number | null;
  qualityLabel: string;
  dominantPollutant: string;
  observedAt: string;
  sourceName: string;
  sourceUrl: string;
  pollutants: PollutantVector;
  missingPollutants: string[];
}

export interface PlantState {
  cityKey: string;
  cityName: string;
  lastObservedAt: string;
  sampleCount: number;
  observationDates: string[];
  averageStress: number;
  pollutantMemory: PlantMemory;
  heightScore: number;
  leafScore: number;
  colorScore: number;
  droopScore: number;
  bloomScore: number;
  particleScore: number;
  updatedAt: string;
}

export interface StoredCityRecord {
  cityKey: string;
  cityName: string;
  snapshot: AqiSnapshot | null;
  plant: PlantState;
}

export interface PollutantDisplayItem {
  key: PollutantKey;
  name: string;
  valueText: string;
  stress: number;
  missing: boolean;
}

export function createEmptyPollutants(): PollutantVector {
  return {
    pm25: null,
    pm10: null,
    o3: null,
    no2: null,
    so2: null,
    co: null
  };
}

export function createInitialMemory(): PlantMemory {
  return {
    pm25: 0.28,
    pm10: 0.24,
    o3: 0.22,
    no2: 0.20,
    so2: 0.16,
    co: 0.14
  };
}

export function createInitialPlantState(cityKey: string, cityName: string): PlantState {
  return {
    cityKey,
    cityName,
    lastObservedAt: '',
    sampleCount: 0,
    observationDates: [],
    averageStress: 0.22,
    pollutantMemory: createInitialMemory(),
    heightScore: 0.78,
    leafScore: 0.72,
    colorScore: 0.76,
    droopScore: 0.16,
    bloomScore: 0.42,
    particleScore: 0.16,
    updatedAt: ''
  };
}

export function getPollutantLabel(key: PollutantKey): string {
  switch (key) {
    case 'pm25':
      return 'PM2.5';
    case 'pm10':
      return 'PM10';
    case 'o3':
      return 'O3';
    case 'no2':
      return 'NO2';
    case 'so2':
      return 'SO2';
    case 'co':
      return 'CO';
    default:
      return key;
  }
}

export function getPollutantValue(pollutants: PollutantVector, key: PollutantKey): number | null {
  switch (key) {
    case 'pm25':
      return pollutants.pm25;
    case 'pm10':
      return pollutants.pm10;
    case 'o3':
      return pollutants.o3;
    case 'no2':
      return pollutants.no2;
    case 'so2':
      return pollutants.so2;
    case 'co':
      return pollutants.co;
    default:
      return null;
  }
}

export function getMemoryValue(memory: PlantMemory, key: PollutantKey): number {
  switch (key) {
    case 'pm25':
      return memory.pm25;
    case 'pm10':
      return memory.pm10;
    case 'o3':
      return memory.o3;
    case 'no2':
      return memory.no2;
    case 'so2':
      return memory.so2;
    case 'co':
      return memory.co;
    default:
      return 0;
  }
}

export function setMemoryValue(memory: PlantMemory, key: PollutantKey, value: number): void {
  switch (key) {
    case 'pm25':
      memory.pm25 = value;
      break;
    case 'pm10':
      memory.pm10 = value;
      break;
    case 'o3':
      memory.o3 = value;
      break;
    case 'no2':
      memory.no2 = value;
      break;
    case 'so2':
      memory.so2 = value;
      break;
    case 'co':
      memory.co = value;
      break;
    default:
      break;
  }
}
