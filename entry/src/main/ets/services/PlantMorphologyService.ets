import { PlantGenome, PlantState } from '../models/AqiModels';
import { getPlantMaturity, normalizePlantState } from './PlantAlgorithm';

export interface PlantPalette {
  background: string;
  stem: string;
  stemDark: string;
  leaf: string;
  leafAccent: string;
  leafShadow: string;
  bloom: string;
  lesion: string;
  soil: string;
  soilDark: string;
  particle: string;
}

export interface MorphBranch {
  startX: number;
  startY: number;
  controlX: number;
  controlY: number;
  endX: number;
  endY: number;
  width: number;
  color: string;
  alpha: number;
  rupture: number;
}

export interface MorphLeaf {
  rootX: number;
  rootY: number;
  dirX: number;
  dirY: number;
  length: number;
  width: number;
  color: string;
  alpha: number;
  damage: number;
}

export interface MorphBud {
  x: number;
  y: number;
  radius: number;
  color: string;
  alpha: number;
}

export interface PlantMorphology {
  genome: PlantGenome;
  palette: PlantPalette;
  branches: MorphBranch[];
  leaves: MorphLeaf[];
  buds: MorphBud[];
  rootX: number;
  rootY: number;
  growth: number;
  stress: number;
  distortion: number;
  particleScore: number;
}

interface GrowthCounter {
  value: number;
}

class DeterministicRandom {
  private state: number;

  constructor(seed: number) {
    this.state = seed <= 0 ? 1 : seed;
  }

  next(): number {
    this.state = this.state * 48271 % 2147483647;
    return this.state / 2147483647;
  }

  between(min: number, max: number): number {
    return min + (max - min) * this.next();
  }
}

export class PlantMorphologyService {
  buildGenome(installSeed: string, cityKey: string): PlantGenome {
    const seedText = `${installSeed}:${cityKey}`;
    const rng = new DeterministicRandom(this.hashString(seedText));
    const primaryHue = rng.between(34, 326);
    return {
      seed: seedText,
      branchAngle: rng.between(0.28, 1.12),
      branchSpread: rng.between(0.55, 1.58),
      segmentScale: rng.between(0.64, 1.42),
      curl: rng.between(-1.36, 1.36),
      asymmetry: rng.between(-0.88, 0.88),
      leafRhythm: rng.between(0.44, 1.88),
      alienSensitivity: rng.between(0.54, 1.72),
      primaryHue,
      secondaryHue: this.wrapHue(primaryHue + rng.between(42, 224)),
      stemHueOffset: rng.between(-62, 64),
      bloomHue: this.wrapHue(primaryHue + rng.between(76, 286)),
      colorShiftSensitivity: rng.between(0.52, 1.74)
    };
  }

  buildMorphology(
    plantInput: PlantState,
    installSeed: string,
    width: number,
    height: number,
    time: number,
    offsetX: number,
    verticalShift: number,
    pulse: number
  ): PlantMorphology {
    const plant = normalizePlantState(plantInput);
    const genome = this.buildGenome(installSeed, plant.cityKey);
    const palette = this.buildPalette(plant, genome);
    const maturity = getPlantMaturity(plant);
    const distortion = this.getDistortionScore(plant, genome);
    const growth = 0.20 + maturity * 0.80;
    const rootX = width / 2 + offsetX;
    const rootY = height - 40 - verticalShift;
    const result: PlantMorphology = {
      genome,
      palette,
      branches: [],
      leaves: [],
      buds: [],
      rootX,
      rootY,
      growth,
      stress: plant.averageStress,
      distortion,
      particleScore: plant.particleScore
    };

    const maxDepth = this.getIterationDepth(maturity);
    const heightScore = 0.62 + plant.heightScore * 0.38;
    const stressShorten = 1 - plant.pollutantMemory.pm25 * 0.18 - distortion * 0.10;
    const baseLength = (58 + maturity * 92) * genome.segmentScale * heightScore * stressShorten;
    const baseWidth = 4.4 + growth * 4.8;
    const pulseCurve = Math.sin((1 - pulse) * Math.PI);
    const pulseDirection = genome.asymmetry >= 0 ? 1 : -1;
    const interactionSwing = pulseCurve * pulseDirection * (0.04 + (1 - maturity) * 0.24);
    const initialAngle = -Math.PI / 2 + genome.asymmetry * 0.30 + plant.droopScore * 0.26 + interactionSwing;
    const counter: GrowthCounter = { value: 1 };
    this.growBranch(result, plant, genome, counter, 0, maxDepth, rootX, rootY, initialAngle, baseLength, baseWidth, time);

    if (pulse > 0) {
      result.buds.push({
        x: rootX,
        y: rootY - baseLength * (0.8 + maturity * 0.4),
        radius: 18 + growth * 16 + (1 - pulse) * 26,
        color: palette.bloom,
        alpha: pulse * 0.30
      });
    }

    return result;
  }

  buildPaletteForPlant(plantInput: PlantState, installSeed: string): PlantPalette {
    const plant = normalizePlantState(plantInput);
    const genome = this.buildGenome(installSeed, plant.cityKey);
    return this.buildPalette(plant, genome);
  }

  getDistortionScore(plantInput: PlantState, genome: PlantGenome): number {
    const plant = normalizePlantState(plantInput);
    const memory = plant.pollutantMemory;
    const stressBase = this.clamp((plant.averageStress - 0.24) * 1.48);
    const pollutantShapePressure = memory.pm25 * 0.18 + memory.pm10 * 0.16 + memory.no2 * 0.20 +
      memory.so2 * 0.13 + memory.o3 * 0.12 + memory.co * 0.08;
    return this.clamp((stressBase + pollutantShapePressure * 0.42) * genome.alienSensitivity);
  }

  getColorPollutionShift(plantInput: PlantState, genome: PlantGenome): number {
    const plant = normalizePlantState(plantInput);
    const memory = plant.pollutantMemory;
    return this.clamp((plant.averageStress * 0.78 + memory.o3 * 0.14 + memory.pm10 * 0.08) *
      genome.colorShiftSensitivity);
  }

  private getIterationDepth(maturity: number): number {
    if (maturity < 0.22) {
      return 1;
    }
    if (maturity < 0.50) {
      return 2;
    }
    if (maturity < 0.86) {
      return 3;
    }
    return 4;
  }

  private growBranch(
    result: PlantMorphology,
    plant: PlantState,
    genome: PlantGenome,
    counter: GrowthCounter,
    level: number,
    maxDepth: number,
    startX: number,
    startY: number,
    angle: number,
    length: number,
    width: number,
    time: number
  ): void {
    const nodeId = counter.value;
    counter.value += 1;
    const maturity = getPlantMaturity(plant);
    const vitality = 1 - plant.averageStress;
    const distortion = result.distortion;
    const noise = this.noise(genome.seed, nodeId * 17);
    const kink = (noise - 0.5) * distortion * 0.95 + genome.curl * 0.16 + plant.droopScore * 0.24;
    const sway = Math.sin(time * 0.72 + nodeId * 0.83) * (0.025 + vitality * 0.028) * (1 - distortion * 0.35);
    const endAngle = angle + kink + sway;
    const endX = startX + Math.cos(endAngle) * length;
    const endY = startY + Math.sin(endAngle) * length;
    const controlNoise = this.noise(genome.seed, nodeId * 31) - 0.5;
    const controlAngle = angle + kink * 0.56 + controlNoise * distortion * 0.74;
    const controlDistance = length * (0.44 + this.noise(genome.seed, nodeId * 43) * 0.16);
    const controlX = startX + Math.cos(controlAngle) * controlDistance;
    const controlY = startY + Math.sin(controlAngle) * controlDistance;
    const rupture = distortion < 0.48 ? 0 : this.clamp((distortion - 0.48) * 1.55 + (noise - 0.5) * 0.42);

    result.branches.push({
      startX,
      startY,
      controlX,
      controlY,
      endX,
      endY,
      width,
      color: level === 0 ? result.palette.stemDark : result.palette.stem,
      alpha: 0.74 + vitality * 0.24 - rupture * 0.18,
      rupture
    });

    this.addLeaves(result, plant, genome, nodeId, level, startX, startY, controlX, controlY, endX, endY);

    if (level >= maxDepth) {
      if (maturity > 0.66 && vitality > 0.32) {
        result.buds.push({
          x: endX,
          y: endY,
          radius: 2.6 + plant.bloomScore * 4.6 * maturity,
          color: result.palette.bloom,
          alpha: 0.18 + vitality * 0.32
        });
      }
      return;
    }

    const nextLength = length * (0.68 + genome.segmentScale * 0.08 - plant.averageStress * 0.06);
    const nextWidth = Math.max(1.4, width * (0.68 - distortion * 0.08));
    const continuationAngle = endAngle + (this.noise(genome.seed, nodeId * 59) - 0.5) * (0.16 + distortion * 0.42);
    this.growBranch(result, plant, genome, counter, level + 1, maxDepth, endX, endY, continuationAngle,
      nextLength, nextWidth, time);

    if (maturity < 0.18) {
      return;
    }

    let branchPairs = 1;
    if (maturity > 0.62 && level <= 1) {
      branchPairs = 2;
    }
    if (level >= 3 && distortion < 0.62) {
      branchPairs = 0;
    }
    for (let i = 0; i < branchPairs; i++) {
      const sideSeed = this.noise(genome.seed, nodeId * 73 + i * 11);
      let side = i % 2 === 0 ? -1 : 1;
      if (distortion > 0.58 && sideSeed > 0.62) {
        side *= -1;
      }
      const angleNoise = (sideSeed - 0.5) * (0.22 + distortion * 0.85);
      const sideAngle = endAngle + side * genome.branchAngle * genome.branchSpread +
        genome.asymmetry * 0.36 + angleNoise;
      const sideLength = length * (0.38 + maturity * 0.20 + sideSeed * 0.12) * (1 - plant.pollutantMemory.pm25 * 0.08);
      const sideWidth = Math.max(1.2, width * (0.46 + maturity * 0.10));
      this.growBranch(result, plant, genome, counter, level + 1, maxDepth, endX, endY, sideAngle,
        sideLength, sideWidth, time);
    }
  }

  private addLeaves(
    result: PlantMorphology,
    plant: PlantState,
    genome: PlantGenome,
    nodeId: number,
    level: number,
    startX: number,
    startY: number,
    controlX: number,
    controlY: number,
    endX: number,
    endY: number
  ): void {
    const maturity = getPlantMaturity(plant);
    const distortion = result.distortion;
    const leafBase = maturity < 0.24 ? 1 : 1 + Math.round(maturity * 2 + plant.leafScore * 1.6);
    const count = level === 0 && maturity < 0.24 ? 1 : Math.max(1, Math.round(leafBase * genome.leafRhythm));
    for (let i = 0; i < count; i++) {
      const progress = (i + 1) / (count + 1);
      const x = this.quadraticPoint(startX, controlX, endX, progress);
      const y = this.quadraticPoint(startY, controlY, endY, progress);
      const tangentX = this.quadraticTangent(startX, controlX, endX, progress);
      const tangentY = this.quadraticTangent(startY, controlY, endY, progress);
      const tangentLength = Math.max(1, Math.sqrt(tangentX * tangentX + tangentY * tangentY));
      const normalX = -tangentY / tangentLength;
      const normalY = tangentX / tangentLength;
      const leafNoise = this.noise(genome.seed, nodeId * 101 + i * 13);
      let side = (i + level) % 2 === 0 ? -1 : 1;
      if (distortion > 0.55 && leafNoise > 0.58) {
        side *= -1;
      }
      const tangentPull = distortion * (leafNoise - 0.5) * 0.72;
      const dirX = normalX * side + tangentX / tangentLength * tangentPull;
      const dirY = normalY * side + tangentY / tangentLength * tangentPull;
      const damage = this.clamp(distortion * (0.32 + plant.pollutantMemory.pm10 * 0.36 +
        plant.pollutantMemory.o3 * 0.24) * (0.58 + leafNoise * 0.72));
      const length = (9 + maturity * 21 + plant.leafScore * 8) * (0.72 + (1 - progress) * 0.24) *
        (1 - damage * 0.30);
      const width = (3.2 + maturity * 5.6) * (1 - damage * 0.18);
      result.leaves.push({
        rootX: x,
        rootY: y,
        dirX,
        dirY,
        length,
        width,
        color: damage > 0.46 && leafNoise > 0.48 ? result.palette.leafAccent : result.palette.leaf,
        alpha: 0.58 + plant.leafScore * 0.34 - damage * 0.18,
        damage
      });
    }
  }

  private buildPalette(plant: PlantState, genome: PlantGenome): PlantPalette {
    const colorShift = this.getColorPollutionShift(plant, genome);
    const vitality = 1 - plant.averageStress;
    const leafHue = this.wrapHue(genome.primaryHue + plant.pollutantMemory.o3 * 36 - colorShift * 42);
    const accentHue = this.wrapHue(genome.secondaryHue + colorShift * 92);
    const stemHue = this.wrapHue(leafHue + genome.stemHueOffset - colorShift * 18);
    const leafSaturation = this.clamp(0.46 + plant.colorScore * 0.30 - colorShift * 0.42, 0.12, 0.78);
    const leafLight = this.clamp(0.36 + vitality * 0.18 - colorShift * 0.12, 0.23, 0.58);
    const accentSaturation = this.clamp(leafSaturation * (0.72 - colorShift * 0.16), 0.08, 0.62);
    const accentLight = this.clamp(leafLight - 0.08 - colorShift * 0.04, 0.18, 0.46);
    const backgroundSat = this.clamp(0.18 - colorShift * 0.08, 0.06, 0.20);
    const backgroundLight = this.clamp(0.92 - colorShift * 0.08, 0.82, 0.94);

    return {
      background: this.hslString(leafHue, backgroundSat, backgroundLight),
      stem: this.hslString(stemHue, this.clamp(leafSaturation * 0.72, 0.12, 0.52), this.clamp(leafLight - 0.12, 0.18, 0.38)),
      stemDark: this.hslString(stemHue, this.clamp(leafSaturation * 0.80, 0.16, 0.58), this.clamp(leafLight - 0.20, 0.14, 0.30)),
      leaf: this.hslString(leafHue, leafSaturation, leafLight),
      leafAccent: this.hslString(accentHue, accentSaturation, accentLight),
      leafShadow: this.hslString(leafHue, this.clamp(leafSaturation * 0.62, 0.10, 0.44), this.clamp(leafLight - 0.15, 0.16, 0.34)),
      bloom: this.hslString(genome.bloomHue, this.clamp(0.46 + vitality * 0.28 - colorShift * 0.16, 0.18, 0.74),
        this.clamp(0.46 + vitality * 0.16, 0.32, 0.64)),
      lesion: this.hslString(16 + plant.pollutantMemory.o3 * 42, this.clamp(0.36 + colorShift * 0.34, 0.28, 0.78),
        this.clamp(0.28 + colorShift * 0.08, 0.24, 0.42)),
      soil: this.hslString(26 + colorShift * 12, 0.30, 0.45 - colorShift * 0.05),
      soilDark: this.hslString(28 + colorShift * 10, 0.28, 0.25 - colorShift * 0.03),
      particle: colorShift > 0.48 ? '#5F5C58' : '#6C716C'
    };
  }

  private hashString(value: string): number {
    let hash = 7;
    for (let i = 0; i < value.length; i++) {
      hash = (hash * 31 + value.charCodeAt(i)) % 2147483647;
    }
    return hash <= 0 ? 1 : hash;
  }

  private noise(seed: string, salt: number): number {
    const rng = new DeterministicRandom(this.hashString(`${seed}:${salt}`));
    return rng.next();
  }

  private quadraticPoint(start: number, control: number, end: number, progress: number): number {
    const inverse = 1 - progress;
    return inverse * inverse * start + 2 * inverse * progress * control + progress * progress * end;
  }

  private quadraticTangent(start: number, control: number, end: number, progress: number): number {
    return 2 * (1 - progress) * (control - start) + 2 * progress * (end - control);
  }

  private hslString(hue: number, saturation: number, lightness: number): string {
    const h = this.wrapHue(hue) / 360;
    const s = this.clamp(saturation);
    const l = this.clamp(lightness);
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    const p = 2 * l - q;
    const r = this.hueToRgb(p, q, h + 1 / 3);
    const g = this.hueToRgb(p, q, h);
    const b = this.hueToRgb(p, q, h - 1 / 3);
    return `rgb(${Math.round(r * 255)},${Math.round(g * 255)},${Math.round(b * 255)})`;
  }

  private hueToRgb(p: number, q: number, tInput: number): number {
    let t = tInput;
    if (t < 0) {
      t += 1;
    }
    if (t > 1) {
      t -= 1;
    }
    if (t < 1 / 6) {
      return p + (q - p) * 6 * t;
    }
    if (t < 1 / 2) {
      return q;
    }
    if (t < 2 / 3) {
      return p + (q - p) * (2 / 3 - t) * 6;
    }
    return p;
  }

  private wrapHue(hue: number): number {
    let value = hue % 360;
    if (value < 0) {
      value += 360;
    }
    return value;
  }

  private clamp(value: number, min: number = 0, max: number = 1): number {
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }
}
