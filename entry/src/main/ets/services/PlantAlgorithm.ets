import {
  AqiSnapshot,
  PlantMemory,
  PlantState,
  PollutantDisplayItem,
  PollutantKey,
  PollutantVector,
  POLLUTANT_KEYS,
  createInitialPlantState,
  getMemoryValue,
  getPollutantLabel,
  getPollutantValue,
  setMemoryValue
} from '../models/AqiModels';

const ALPHA: number = 0.18;

function clamp(value: number, min: number = 0, max: number = 1): number {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

function getWeight(key: PollutantKey): number {
  switch (key) {
    case 'pm25':
      return 0.28;
    case 'pm10':
      return 0.20;
    case 'o3':
      return 0.18;
    case 'no2':
      return 0.14;
    case 'so2':
      return 0.10;
    case 'co':
      return 0.10;
    default:
      return 0;
  }
}

export function normalizePollutantIndex(value: number | null): number {
  if (value === null || value < 0) {
    return -1;
  }
  if (value <= 50) {
    return clamp(value / 50 * 0.18);
  }
  if (value <= 100) {
    return 0.18 + (value - 50) / 50 * 0.22;
  }
  if (value <= 150) {
    return 0.40 + (value - 100) / 50 * 0.20;
  }
  if (value <= 200) {
    return 0.60 + (value - 150) / 50 * 0.18;
  }
  if (value <= 300) {
    return 0.78 + (value - 200) / 100 * 0.14;
  }
  return clamp(0.92 + (value - 300) / 200 * 0.08);
}

export function getQualityLabel(aqi: number | null): string {
  if (aqi === null || aqi < 0) {
    return '暂无';
  }
  if (aqi <= 50) {
    return '优';
  }
  if (aqi <= 100) {
    return '良';
  }
  if (aqi <= 150) {
    return '轻度污染';
  }
  if (aqi <= 200) {
    return '中度污染';
  }
  if (aqi <= 300) {
    return '重度污染';
  }
  return '严重污染';
}

export function getQualityColor(aqi: number | null): string {
  if (aqi === null || aqi < 0) {
    return '#7A8288';
  }
  if (aqi <= 50) {
    return '#2F9E6D';
  }
  if (aqi <= 100) {
    return '#7BAF42';
  }
  if (aqi <= 150) {
    return '#D6A53A';
  }
  if (aqi <= 200) {
    return '#D2743F';
  }
  if (aqi <= 300) {
    return '#B94F5F';
  }
  return '#7F4E68';
}

function cloneMemory(memory: PlantMemory): PlantMemory {
  if (memory === undefined || memory === null) {
    return createInitialPlantState('', '').pollutantMemory;
  }
  const fallback = createInitialPlantState('', '').pollutantMemory;
  return {
    pm25: clamp(safeNumber(memory.pm25, fallback.pm25)),
    pm10: clamp(safeNumber(memory.pm10, fallback.pm10)),
    o3: clamp(safeNumber(memory.o3, fallback.o3)),
    no2: clamp(safeNumber(memory.no2, fallback.no2)),
    so2: clamp(safeNumber(memory.so2, fallback.so2)),
    co: clamp(safeNumber(memory.co, fallback.co))
  };
}

function calculateAverageStress(memory: PlantMemory): number {
  let sum = 0;
  POLLUTANT_KEYS.forEach((key: PollutantKey) => {
    sum += getMemoryValue(memory, key) * getWeight(key);
  });
  return clamp(sum);
}

function getObservationDateKey(observedAt: string): string {
  if (observedAt.length >= 10) {
    return observedAt.substring(0, 10);
  }
  return new Date().toISOString().substring(0, 10);
}

export function getPlantObservationDates(plant: PlantState): string[] {
  if (plant.observationDates !== undefined && plant.observationDates !== null && plant.observationDates.length > 0) {
    return plant.observationDates;
  }
  if (plant.lastObservedAt !== undefined && plant.lastObservedAt !== null && plant.lastObservedAt.length > 0) {
    return [getObservationDateKey(plant.lastObservedAt)];
  }
  return [];
}

function safeNumber(value: number | undefined | null, fallback: number): number {
  if (value === undefined || value === null || isNaN(value)) {
    return fallback;
  }
  return value;
}

export function normalizePlantState(plant: PlantState): PlantState {
  const cityKey = plant.cityKey === undefined || plant.cityKey === null ? 'unknown' : plant.cityKey;
  const cityName = plant.cityName === undefined || plant.cityName === null ? '未知城市' : plant.cityName;
  const fallback = createInitialPlantState(cityKey, cityName);
  const dates = getPlantObservationDates(plant);
  return {
    cityKey,
    cityName,
    lastObservedAt: plant.lastObservedAt === undefined || plant.lastObservedAt === null ? '' : plant.lastObservedAt,
    sampleCount: Math.max(0, Math.round(safeNumber(plant.sampleCount, fallback.sampleCount))),
    observationDates: dates,
    averageStress: clamp(safeNumber(plant.averageStress, fallback.averageStress)),
    pollutantMemory: cloneMemory(plant.pollutantMemory),
    heightScore: clamp(safeNumber(plant.heightScore, fallback.heightScore)),
    leafScore: clamp(safeNumber(plant.leafScore, fallback.leafScore)),
    colorScore: clamp(safeNumber(plant.colorScore, fallback.colorScore)),
    droopScore: clamp(safeNumber(plant.droopScore, fallback.droopScore)),
    bloomScore: clamp(safeNumber(plant.bloomScore, fallback.bloomScore)),
    particleScore: clamp(safeNumber(plant.particleScore, fallback.particleScore)),
    updatedAt: plant.updatedAt === undefined || plant.updatedAt === null ? '' : plant.updatedAt
  };
}

export function getPlantGrowthDays(plant: PlantState): number {
  return getPlantObservationDates(plant).length;
}

export function getPlantMaturity(plant: PlantState): number {
  return clamp(getPlantGrowthDays(plant) / 7);
}

function appendObservationDate(plant: PlantState, observedAt: string): string[] {
  const dateKey = getObservationDateKey(observedAt);
  const dates = getPlantObservationDates(plant).slice();
  if (!dates.includes(dateKey)) {
    dates.push(dateKey);
  }
  return dates.sort();
}

export function updatePlantWithSnapshot(current: PlantState | null, snapshot: AqiSnapshot): PlantState {
  const base = current === null ? createInitialPlantState(snapshot.cityKey, snapshot.cityName) : normalizePlantState(current);
  if (base.lastObservedAt === snapshot.observedAt && snapshot.observedAt.length > 0) {
    return {
      cityKey: base.cityKey,
      cityName: base.cityName,
      lastObservedAt: base.lastObservedAt,
      sampleCount: base.sampleCount,
      observationDates: getPlantObservationDates(base),
      averageStress: base.averageStress,
      pollutantMemory: cloneMemory(base.pollutantMemory),
      heightScore: base.heightScore,
      leafScore: base.leafScore,
      colorScore: base.colorScore,
      droopScore: base.droopScore,
      bloomScore: base.bloomScore,
      particleScore: base.particleScore,
      updatedAt: base.updatedAt
    };
  }

  const nextMemory = cloneMemory(base.pollutantMemory);
  const observationDates = appendObservationDate(base, snapshot.observedAt);
  POLLUTANT_KEYS.forEach((key: PollutantKey) => {
    const rawValue = getPollutantValue(snapshot.pollutants, key);
    const stress = normalizePollutantIndex(rawValue);
    if (stress >= 0) {
      const previous = getMemoryValue(nextMemory, key);
      setMemoryValue(nextMemory, key, previous * (1 - ALPHA) + stress * ALPHA);
    }
  });

  const stress = calculateAverageStress(nextMemory);
  const vitality = 1 - stress;
  const pmFine = nextMemory.pm25;
  const oxidant = nextMemory.o3;

  return {
    cityKey: snapshot.cityKey,
    cityName: snapshot.cityName,
    lastObservedAt: snapshot.observedAt,
    sampleCount: base.sampleCount + 1,
    observationDates,
    averageStress: stress,
    pollutantMemory: nextMemory,
    heightScore: clamp(0.34 + vitality * 0.58 - pmFine * 0.08),
    leafScore: clamp(0.28 + vitality * 0.66 - nextMemory.pm10 * 0.08),
    colorScore: clamp(0.22 + vitality * 0.76 - oxidant * 0.04),
    droopScore: clamp(0.08 + stress * 0.78 + pmFine * 0.08),
    bloomScore: clamp(0.08 + vitality * 0.62 - stress * 0.10),
    particleScore: clamp(0.08 + stress * 0.86),
    updatedAt: new Date().toISOString()
  };
}

export function buildPollutantItems(pollutants: PollutantVector | null, memory: PlantMemory): PollutantDisplayItem[] {
  return POLLUTANT_KEYS.map((key: PollutantKey): PollutantDisplayItem => {
    const value = pollutants === null ? null : getPollutantValue(pollutants, key);
    return {
      key,
      name: getPollutantLabel(key),
      valueText: value === null ? '缺失' : Math.round(value).toString(),
      stress: value === null ? getMemoryValue(memory, key) : normalizePollutantIndex(value),
      missing: value === null
    };
  });
}
