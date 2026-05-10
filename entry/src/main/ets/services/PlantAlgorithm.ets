import {
  AqiSnapshot,
  PlantMemory,
  PlantSampleCounts,
  PlantState,
  PollutantDisplayItem,
  PollutantKey,
  PollutantVector,
  POLLUTANT_KEYS,
  RecentStressSample,
  createInitialMemory,
  createInitialPlantState,
  createInitialSampleCounts,
  getMemoryValue,
  getPollutantLabel,
  getPollutantValue,
  setMemoryValue
} from '../models/AqiModels';

export const PLANT_MATURITY_DAYS: number = 14;
const RECENT_MEMORY_DAYS: number = 14;
const LIFETIME_MEMORY_WEIGHT: number = 0.60;
const RECENT_MEMORY_WEIGHT: number = 0.35;
const LATEST_MEMORY_WEIGHT: number = 0.05;

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
    return clamp(value / 50 * 0.22);
  }
  if (value <= 100) {
    return 0.22 + (value - 50) / 50 * 0.30;
  }
  if (value <= 150) {
    return 0.52 + (value - 100) / 50 * 0.20;
  }
  if (value <= 200) {
    return 0.72 + (value - 150) / 50 * 0.14;
  }
  if (value <= 300) {
    return 0.86 + (value - 200) / 100 * 0.10;
  }
  return clamp(0.96 + (value - 300) / 300 * 0.04);
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
    return createInitialMemory();
  }
  const fallback = createInitialMemory();
  return {
    pm25: clamp(safeNumber(memory.pm25, fallback.pm25)),
    pm10: clamp(safeNumber(memory.pm10, fallback.pm10)),
    o3: clamp(safeNumber(memory.o3, fallback.o3)),
    no2: clamp(safeNumber(memory.no2, fallback.no2)),
    so2: clamp(safeNumber(memory.so2, fallback.so2)),
    co: clamp(safeNumber(memory.co, fallback.co))
  };
}

function cloneSampleCounts(counts: PlantSampleCounts | undefined | null, fallbackCount: number = 0): PlantSampleCounts {
  if (counts === undefined || counts === null) {
    return {
      pm25: fallbackCount,
      pm10: fallbackCount,
      o3: fallbackCount,
      no2: fallbackCount,
      so2: fallbackCount,
      co: fallbackCount
    };
  }
  return {
    pm25: Math.max(0, Math.round(safeNumber(counts.pm25, fallbackCount))),
    pm10: Math.max(0, Math.round(safeNumber(counts.pm10, fallbackCount))),
    o3: Math.max(0, Math.round(safeNumber(counts.o3, fallbackCount))),
    no2: Math.max(0, Math.round(safeNumber(counts.no2, fallbackCount))),
    so2: Math.max(0, Math.round(safeNumber(counts.so2, fallbackCount))),
    co: Math.max(0, Math.round(safeNumber(counts.co, fallbackCount)))
  };
}

function getSampleCountValue(counts: PlantSampleCounts, key: PollutantKey): number {
  switch (key) {
    case 'pm25':
      return counts.pm25;
    case 'pm10':
      return counts.pm10;
    case 'o3':
      return counts.o3;
    case 'no2':
      return counts.no2;
    case 'so2':
      return counts.so2;
    case 'co':
      return counts.co;
    default:
      return 0;
  }
}

function setSampleCountValue(counts: PlantSampleCounts, key: PollutantKey, value: number): void {
  switch (key) {
    case 'pm25':
      counts.pm25 = value;
      break;
    case 'pm10':
      counts.pm10 = value;
      break;
    case 'o3':
      counts.o3 = value;
      break;
    case 'no2':
      counts.no2 = value;
      break;
    case 'so2':
      counts.so2 = value;
      break;
    case 'co':
      counts.co = value;
      break;
    default:
      break;
  }
}

function cloneRecentStressSample(sample: RecentStressSample): RecentStressSample {
  return {
    dateKey: sample.dateKey === undefined || sample.dateKey === null ? '' : sample.dateKey,
    sampleCount: Math.max(0, Math.round(safeNumber(sample.sampleCount, 0))),
    pollutantStress: cloneMemory(sample.pollutantStress),
    pollutantSampleCounts: cloneSampleCounts(sample.pollutantSampleCounts)
  };
}

function trimRecentStressSamples(samples: RecentStressSample[]): RecentStressSample[] {
  samples.sort((left: RecentStressSample, right: RecentStressSample): number => {
    if (left.dateKey < right.dateKey) {
      return -1;
    }
    if (left.dateKey > right.dateKey) {
      return 1;
    }
    return 0;
  });
  while (samples.length > RECENT_MEMORY_DAYS) {
    samples.splice(0, 1);
  }
  return samples;
}

function cloneRecentStressSamples(samples: RecentStressSample[] | undefined | null): RecentStressSample[] {
  if (samples === undefined || samples === null || samples.length === 0) {
    return [];
  }
  const result: RecentStressSample[] = [];
  for (let i = 0; i < samples.length; i++) {
    const sample = cloneRecentStressSample(samples[i]);
    if (sample.dateKey.length > 0) {
      result.push(sample);
    }
  }
  return trimRecentStressSamples(result);
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
  const sampleCount = Math.max(0, Math.round(safeNumber(plant.sampleCount, fallback.sampleCount)));
  const visualMemory = cloneMemory(plant.pollutantMemory);
  const lifetimeMemory = plant.lifetimePollutantMemory === undefined || plant.lifetimePollutantMemory === null ?
    cloneMemory(visualMemory) : cloneMemory(plant.lifetimePollutantMemory);
  const lifetimeCounts = plant.lifetimePollutantSampleCounts === undefined ||
    plant.lifetimePollutantSampleCounts === null ? cloneSampleCounts(null, sampleCount) :
    cloneSampleCounts(plant.lifetimePollutantSampleCounts);
  return {
    cityKey,
    cityName,
    genomeSeed: plant.genomeSeed === undefined || plant.genomeSeed === null ? fallback.genomeSeed : plant.genomeSeed,
    lastObservedAt: plant.lastObservedAt === undefined || plant.lastObservedAt === null ? '' : plant.lastObservedAt,
    sampleCount,
    observationDates: dates,
    averageStress: clamp(safeNumber(plant.averageStress, fallback.averageStress)),
    pollutantMemory: visualMemory,
    lifetimePollutantMemory: lifetimeMemory,
    lifetimePollutantSampleCounts: lifetimeCounts,
    recentStressSamples: cloneRecentStressSamples(plant.recentStressSamples),
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
  return clamp(getPlantGrowthDays(plant) / PLANT_MATURITY_DAYS);
}

function getMaxPollutantStress(memory: PlantMemory): number {
  let max = 0;
  POLLUTANT_KEYS.forEach((key: PollutantKey) => {
    const value = getMemoryValue(memory, key);
    if (value > max) {
      max = value;
    }
  });
  return clamp(max);
}

function calculateMatureStageStress(plant: PlantState): number {
  const memory = plant.pollutantMemory;
  const weightedStress = calculateAverageStress(memory);
  const shapeStress = clamp(memory.pm25 * 0.27 + memory.pm10 * 0.23 + memory.o3 * 0.18 +
    memory.no2 * 0.15 + memory.so2 * 0.09 + memory.co * 0.08);
  const peakStress = getMaxPollutantStress(memory);
  const peakPenalty = peakStress > 0.50 ? (peakStress - 0.50) * 0.34 : 0;
  const imbalancePenalty = Math.max(0, peakStress - weightedStress) * 0.18;
  const memoryStress = weightedStress * 0.30 + shapeStress * 0.28 + peakStress * 0.28 +
    peakPenalty + imbalancePenalty;
  return clamp(Math.max(plant.averageStress, memoryStress));
}

export function getPlantGrowthStageText(plantInput: PlantState): string {
  const plant = normalizePlantState(plantInput);
  const growthDays = getPlantGrowthDays(plant);
  if (growthDays <= 0) {
    return '待发芽';
  }
  if (growthDays <= 2) {
    return '萌芽';
  }
  if (growthDays <= 5) {
    return '幼苗';
  }
  if (growthDays <= 8) {
    return '抽枝';
  }
  if (growthDays <= 11) {
    return '展叶';
  }
  if (growthDays < PLANT_MATURITY_DAYS) {
    return '近成熟';
  }
  const stress = calculateMatureStageStress(plant);
  if (stress < 0.24) {
    return '成熟 · 清朗';
  }
  if (stress < 0.36) {
    return '成熟 · 舒展';
  }
  if (stress < 0.48) {
    return '成熟 · 平稳';
  }
  if (stress < 0.64) {
    return '成熟 · 承压';
  }
  if (stress < 0.86) {
    return '成熟 · 枯化';
  }
  return '成熟 · 异化';
}

function appendObservationDate(plant: PlantState, observedAt: string): string[] {
  const dateKey = getObservationDateKey(observedAt);
  const dates = getPlantObservationDates(plant).slice();
  if (!dates.includes(dateKey)) {
    dates.push(dateKey);
  }
  return dates.sort();
}

function buildLatestStressMemory(pollutants: PollutantVector, fallback: PlantMemory): PlantMemory {
  const latest = cloneMemory(fallback);
  POLLUTANT_KEYS.forEach((key: PollutantKey) => {
    const stress = normalizePollutantIndex(getPollutantValue(pollutants, key));
    if (stress >= 0) {
      setMemoryValue(latest, key, stress);
    }
  });
  return latest;
}

function updateLifetimeMemory(base: PlantState, snapshot: AqiSnapshot): PlantMemory {
  const nextMemory = cloneMemory(base.lifetimePollutantMemory);
  const nextCounts = cloneSampleCounts(base.lifetimePollutantSampleCounts);
  POLLUTANT_KEYS.forEach((key: PollutantKey) => {
    const stress = normalizePollutantIndex(getPollutantValue(snapshot.pollutants, key));
    if (stress >= 0) {
      const count = getSampleCountValue(nextCounts, key);
      const previous = getMemoryValue(nextMemory, key);
      setMemoryValue(nextMemory, key, count <= 0 ? stress : (previous * count + stress) / (count + 1));
      setSampleCountValue(nextCounts, key, count + 1);
    }
  });
  return nextMemory;
}

function updateLifetimeCounts(base: PlantState, snapshot: AqiSnapshot): PlantSampleCounts {
  const nextCounts = cloneSampleCounts(base.lifetimePollutantSampleCounts);
  POLLUTANT_KEYS.forEach((key: PollutantKey) => {
    const stress = normalizePollutantIndex(getPollutantValue(snapshot.pollutants, key));
    if (stress >= 0) {
      const count = getSampleCountValue(nextCounts, key);
      setSampleCountValue(nextCounts, key, count + 1);
    }
  });
  return nextCounts;
}

function upsertRecentStressSample(base: PlantState, snapshot: AqiSnapshot): RecentStressSample[] {
  const dateKey = getObservationDateKey(snapshot.observedAt);
  const samples = cloneRecentStressSamples(base.recentStressSamples);
  let targetIndex = -1;
  for (let i = 0; i < samples.length; i++) {
    if (samples[i].dateKey === dateKey) {
      targetIndex = i;
      break;
    }
  }
  if (targetIndex < 0) {
    samples.push({
      dateKey,
      sampleCount: 0,
      pollutantStress: createInitialMemory(),
      pollutantSampleCounts: createInitialSampleCounts()
    });
    targetIndex = samples.length - 1;
  }

  const sample = samples[targetIndex];
  sample.sampleCount += 1;
  POLLUTANT_KEYS.forEach((key: PollutantKey) => {
    const stress = normalizePollutantIndex(getPollutantValue(snapshot.pollutants, key));
    if (stress >= 0) {
      const count = getSampleCountValue(sample.pollutantSampleCounts, key);
      const previous = getMemoryValue(sample.pollutantStress, key);
      setMemoryValue(sample.pollutantStress, key, count <= 0 ? stress : (previous * count + stress) / (count + 1));
      setSampleCountValue(sample.pollutantSampleCounts, key, count + 1);
    }
  });

  return trimRecentStressSamples(samples);
}

function calculateRecentMemory(samples: RecentStressSample[], fallback: PlantMemory): PlantMemory {
  const recent = cloneMemory(fallback);
  POLLUTANT_KEYS.forEach((key: PollutantKey) => {
    let sum = 0;
    let count = 0;
    for (let i = 0; i < samples.length; i++) {
      if (getSampleCountValue(samples[i].pollutantSampleCounts, key) > 0) {
        sum += getMemoryValue(samples[i].pollutantStress, key);
        count += 1;
      }
    }
    if (count > 0) {
      setMemoryValue(recent, key, sum / count);
    }
  });
  return recent;
}

function blendVisualMemory(lifetime: PlantMemory, recent: PlantMemory, latest: PlantMemory): PlantMemory {
  const visual = cloneMemory(lifetime);
  POLLUTANT_KEYS.forEach((key: PollutantKey) => {
    const value = getMemoryValue(lifetime, key) * LIFETIME_MEMORY_WEIGHT +
      getMemoryValue(recent, key) * RECENT_MEMORY_WEIGHT +
      getMemoryValue(latest, key) * LATEST_MEMORY_WEIGHT;
    setMemoryValue(visual, key, clamp(value));
  });
  return visual;
}

export function updatePlantWithSnapshot(current: PlantState | null, snapshot: AqiSnapshot): PlantState {
  const base = current === null ? createInitialPlantState(snapshot.cityKey, snapshot.cityName) : normalizePlantState(current);
  if (base.lastObservedAt === snapshot.observedAt && snapshot.observedAt.length > 0) {
    return {
      cityKey: base.cityKey,
      cityName: base.cityName,
      genomeSeed: base.genomeSeed,
      lastObservedAt: base.lastObservedAt,
      sampleCount: base.sampleCount,
      observationDates: getPlantObservationDates(base),
      averageStress: base.averageStress,
      pollutantMemory: cloneMemory(base.pollutantMemory),
      lifetimePollutantMemory: cloneMemory(base.lifetimePollutantMemory),
      lifetimePollutantSampleCounts: cloneSampleCounts(base.lifetimePollutantSampleCounts),
      recentStressSamples: cloneRecentStressSamples(base.recentStressSamples),
      heightScore: base.heightScore,
      leafScore: base.leafScore,
      colorScore: base.colorScore,
      droopScore: base.droopScore,
      bloomScore: base.bloomScore,
      particleScore: base.particleScore,
      updatedAt: base.updatedAt
    };
  }

  const observationDates = appendObservationDate(base, snapshot.observedAt);
  const lifetimeMemory = updateLifetimeMemory(base, snapshot);
  const lifetimeCounts = updateLifetimeCounts(base, snapshot);
  const recentSamples = upsertRecentStressSample(base, snapshot);
  const recentMemory = calculateRecentMemory(recentSamples, lifetimeMemory);
  const latestMemory = buildLatestStressMemory(snapshot.pollutants, recentMemory);
  const visualMemory = blendVisualMemory(lifetimeMemory, recentMemory, latestMemory);
  const stress = calculateAverageStress(visualMemory);
  const vitality = 1 - stress;
  const pmFine = visualMemory.pm25;
  const oxidant = visualMemory.o3;

  return {
    cityKey: snapshot.cityKey,
    cityName: snapshot.cityName,
    genomeSeed: base.genomeSeed,
    lastObservedAt: snapshot.observedAt,
    sampleCount: base.sampleCount + 1,
    observationDates,
    averageStress: stress,
    pollutantMemory: visualMemory,
    lifetimePollutantMemory: lifetimeMemory,
    lifetimePollutantSampleCounts: lifetimeCounts,
    recentStressSamples: recentSamples,
    heightScore: clamp(0.28 + vitality * 0.62 - pmFine * 0.12),
    leafScore: clamp(0.18 + vitality * 0.70 - visualMemory.pm10 * 0.18),
    colorScore: clamp(0.18 + vitality * 0.74 - oxidant * 0.12),
    droopScore: clamp(0.10 + stress * 0.82 + pmFine * 0.12),
    bloomScore: clamp(0.06 + vitality * 0.60 - stress * 0.18),
    particleScore: clamp(0.08 + stress * 0.90),
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
