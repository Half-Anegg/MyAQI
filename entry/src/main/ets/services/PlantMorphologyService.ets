import { PlantGenome, PlantState, PlantVisualTraits } from '../models/AqiModels';
import { normalizePlantState } from './PlantAlgorithm';
import { PlantTraitService } from './PlantTraitService';

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
  presence: number;
  health: number;
  twist: number;
  scar: number;
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
  presence: number;
  health: number;
  dust: number;
  bleach: number;
  edgeBurn: number;
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
  traits: PlantVisualTraits;
  branches: MorphBranch[];
  leaves: MorphLeaf[];
  buds: MorphBud[];
  rootX: number;
  rootY: number;
  potBottomY: number;
  growth: number;
  stress: number;
  distortion: number;
  particleScore: number;
  fineParticleScore: number;
  coarseParticleScore: number;
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
  private traitService: PlantTraitService = new PlantTraitService();

  buildGenome(installSeed: string, cityKey: string): PlantGenome {
    const seedText = `${installSeed}:${cityKey}`;
    const rng = new DeterministicRandom(this.hashString(seedText));
    const primaryHue = rng.between(34, 326);
    return {
      seed: seedText,
      branchAngle: rng.between(0.24, 0.88),
      branchSpread: rng.between(0.56, 1.24),
      segmentScale: rng.between(0.64, 1.28),
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
    const traits = this.traitService.buildTraits(plant, genome);
    const palette = this.buildPalette(plant, genome, traits);
    const maturity = traits.maturity;
    const distortion = traits.distortion;
    const growth = 0.20 + maturity * 0.80;
    const rootX = width / 2 + offsetX;
    const potBottomY = height - verticalShift;
    const rootY = potBottomY - 49;
    const result: PlantMorphology = {
      genome,
      palette,
      traits,
      branches: [],
      leaves: [],
      buds: [],
      rootX,
      rootY,
      potBottomY,
      growth,
      stress: traits.averageStress,
      distortion,
      particleScore: traits.particles,
      fineParticleScore: traits.fineHaze,
      coarseParticleScore: traits.coarseDust
    };

    const maxDepth = 4;
    const baseLength = (52 + maturity * 152) * genome.segmentScale * (0.68 + traits.height * 0.38) *
      (1 - distortion * 0.10);
    const baseWidth = 4.4 + growth * 4.8;
    const pulseCurve = Math.sin((1 - pulse) * Math.PI);
    const pulseDirection = genome.asymmetry >= 0 ? 1 : -1;
    const interactionSwing = pulseCurve * pulseDirection * (0.04 + (1 - maturity) * 0.24);
    const initialAngle = -Math.PI / 2 + genome.asymmetry * 0.06 + traits.droop * 0.10 +
      traits.nitrogenTwist * genome.asymmetry * 0.08 + interactionSwing;
    const counter: GrowthCounter = { value: 1 };
    this.growBranch(result, plant, genome, counter, 0, maxDepth, rootX, rootY, initialAngle, baseLength, baseWidth,
      time, 1);

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
    const traits = this.traitService.buildTraits(plant, genome);
    return this.buildPalette(plant, genome, traits);
  }

  getDistortionScore(plantInput: PlantState, genome: PlantGenome): number {
    const plant = normalizePlantState(plantInput);
    return this.traitService.buildTraits(plant, genome).distortion;
  }

  getColorPollutionShift(plantInput: PlantState, genome: PlantGenome): number {
    const plant = normalizePlantState(plantInput);
    return this.traitService.buildTraits(plant, genome).colorShift;
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
    time: number,
    parentPresence: number
  ): void {
    const nodeId = counter.value;
    counter.value += 1;
    const traits = result.traits;
    const maturity = traits.maturity;
    const distortion = result.distortion;
    const noise = this.noise(genome.seed, nodeId * 17);
    const slotNoise = this.noise(genome.seed, nodeId * 19);
    const levelStart = level === 0 ? 0 : 0.10 + level * 0.17 + slotNoise * 0.10;
    const levelPresence = level === 0 ? 0.45 + maturity * 0.55 :
      this.smoothstep(levelStart - 0.14, levelStart + 0.18, maturity);
    const presence = this.clamp(parentPresence * levelPresence *
      (level === 0 ? 1 : (0.42 + traits.branchPresence * 0.58)));
    const healthNoise = this.noise(genome.seed, nodeId * 97) - 0.5;
    const branchHealth = this.clamp(traits.branchHealth - distortion * (0.06 + level * 0.055) +
      healthNoise * 0.12, 0.04, 1);
    const rootStability = level === 0 ? 0.28 : (level === 1 ? 0.56 : 1);
    const droopInfluence = level === 0 ? 0.08 : (level === 1 ? 0.14 : 0.24);
    const localTwist = this.clamp(traits.nitrogenTwist * (0.58 + this.noise(genome.seed, nodeId * 151) * 0.84));
    const terminalBend = level >= maxDepth - 1 ? (this.noise(genome.seed, nodeId * 137) - 0.5) *
      (distortion * 0.62 + localTwist * 1.18 + (1 - branchHealth) * 0.54) : 0;
    const kink = ((noise - 0.5) * distortion * 0.95 + genome.curl * 0.16) * rootStability +
      traits.droop * droopInfluence + localTwist * (noise - 0.5) * 0.28 * rootStability + terminalBend;
    const swayStability = level === 0 ? 0.48 : 1;
    const sway = Math.sin(time * 0.72 + nodeId * 0.83) * (0.010 + traits.sway * 0.034) *
      (1 - distortion * 0.22) * swayStability;
    const endAngle = angle + kink + sway;
    const effectiveLength = length * (0.34 + presence * 0.66) * (0.70 + branchHealth * 0.30);
    const effectiveWidth = Math.max(0.9, width * (0.44 + presence * 0.56) * (0.72 + branchHealth * 0.28));
    const endX = startX + Math.cos(endAngle) * effectiveLength;
    const endY = startY + Math.sin(endAngle) * effectiveLength;
    const controlNoise = this.noise(genome.seed, nodeId * 31) - 0.5;
    const controlAngle = angle + kink * 0.56 + controlNoise * (distortion * 0.64 + localTwist * 0.48) * rootStability;
    const controlDistance = effectiveLength * (0.44 + this.noise(genome.seed, nodeId * 43) * 0.16);
    const controlX = startX + Math.cos(controlAngle) * controlDistance;
    const controlY = startY + Math.sin(controlAngle) * controlDistance;
    const rupture = this.clamp((distortion - 0.26) * 1.36 + localTwist * 0.58 +
      (1 - branchHealth) * 0.42 + (noise - 0.5) * 0.34);
    const scar = this.clamp(rupture * 0.52 + localTwist * 0.56 + traits.sulfurAcid * 0.10);
    const alpha = this.clamp(presence * (0.24 + branchHealth * 0.72) - rupture * 0.08);

    if (alpha > 0.025) {
      result.branches.push({
        startX,
        startY,
        controlX,
        controlY,
        endX,
        endY,
        width: effectiveWidth,
        color: level === 0 ? result.palette.stemDark : result.palette.stem,
        alpha,
        rupture,
        presence,
        health: branchHealth,
        twist: localTwist,
        scar
      });

      this.addLeaves(result, plant, genome, nodeId, level, startX, startY, controlX, controlY, endX, endY, presence,
        branchHealth);
    }

    if (level >= maxDepth) {
      const budAlpha = presence * traits.bloom * (0.38 + branchHealth * 0.62);
      if (budAlpha > 0.05) {
        result.buds.push({
          x: endX,
          y: endY,
          radius: (2.2 + traits.bloom * 4.8 * maturity) * (0.72 + branchHealth * 0.28),
          color: result.palette.bloom,
          alpha: this.clamp(budAlpha * 0.72)
        });
      }
      return;
    }

    if (presence <= 0.018) {
      return;
    }

    const nextLength = length * (0.66 + genome.segmentScale * 0.08 - traits.pollutionPressure * 0.05);
    const nextWidth = Math.max(1.2, width * (0.68 - distortion * 0.06));
    const continuationAngle = endAngle + (this.noise(genome.seed, nodeId * 59) - 0.5) *
      (0.16 + distortion * 0.42) * rootStability;
    this.growBranch(result, plant, genome, counter, level + 1, maxDepth, endX, endY, continuationAngle,
      nextLength, nextWidth, time, presence);

    const sideSlots = this.getSideSlotCount(level);
    for (let i = 0; i < sideSlots; i++) {
      const sideSeed = this.noise(genome.seed, nodeId * 73 + i * 11);
      let side = i % 2 === 0 ? -1 : 1;
      if (distortion > 0.58 && sideSeed > 0.62) {
        side *= -1;
      }
      const sideUnlock = 0.18 + level * 0.16 + i * 0.12 + sideSeed * 0.12;
      const sidePresence = presence * this.smoothstep(sideUnlock - 0.14, sideUnlock + 0.18, maturity) *
        (0.28 + traits.branchPresence * 0.72);
      if (sidePresence <= 0.016) {
        continue;
      }
      const sideOpening = this.clamp(genome.branchAngle * genome.branchSpread + traits.nitrogenTwist * 0.10,
        0.22, 0.82);
      const angleNoise = (sideSeed - 0.5) * (0.18 + distortion * 0.36 + traits.nitrogenTwist * 0.54);
      const sideAngle = endAngle + side * sideOpening + genome.asymmetry * 0.22 +
        traits.nitrogenTwist * side * (sideSeed - 0.5) * 0.24 + angleNoise;
      const sideLength = length * (0.38 + maturity * 0.20 + sideSeed * 0.12) *
        (1 - plant.pollutantMemory.pm25 * 0.12 - distortion * 0.10);
      const sideWidth = Math.max(1.2, width * (0.46 + maturity * 0.10));
      this.growBranch(result, plant, genome, counter, level + 1, maxDepth, endX, endY, sideAngle,
        sideLength, sideWidth, time, sidePresence);
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
    endY: number,
    branchPresence: number,
    branchHealth: number
  ): void {
    const traits = result.traits;
    const maturity = traits.maturity;
    const distortion = result.distortion;
    const leafSlots = level === 0 ? 3 : 4;
    for (let i = 0; i < leafSlots; i++) {
      const progress = (i + 1) / (leafSlots + 1);
      const x = this.quadraticPoint(startX, controlX, endX, progress);
      const y = this.quadraticPoint(startY, controlY, endY, progress);
      const tangentX = this.quadraticTangent(startX, controlX, endX, progress);
      const tangentY = this.quadraticTangent(startY, controlY, endY, progress);
      const tangentLength = Math.max(1, Math.sqrt(tangentX * tangentX + tangentY * tangentY));
      const normalX = -tangentY / tangentLength;
      const normalY = tangentX / tangentLength;
      const leafNoise = this.noise(genome.seed, nodeId * 101 + i * 13);
      const unlock = 0.10 + i * 0.12 + level * 0.055 + leafNoise * 0.10;
      const slotPresence = this.smoothstep(unlock - 0.12, unlock + 0.16, maturity);
      let presence = this.clamp(branchPresence * slotPresence * (0.32 + traits.leafPresence * 0.68) *
        (0.34 + traits.leafDensity * 0.66));
      if (level === 0 && i === 0 && maturity > 0) {
        presence = Math.max(presence, 0.46 + maturity * 0.18);
      }
      const pollutionLeafLoss = this.smoothstep(0.30, 0.78, traits.pollutionPressure + distortion * 0.14 +
        traits.coarseDust * 0.30 + traits.sulfurAcid * 0.10);
      const slotHardiness = 0.24 + leafNoise * 0.58 + (level === 0 ? 0.10 : 0) + (i === 0 ? 0.08 : 0);
      const leafSurvival = 1 - this.smoothstep(slotHardiness - 0.18, slotHardiness + 0.18, pollutionLeafLoss);
      presence = this.clamp(presence * (0.12 + leafSurvival * 0.88));
      if (presence <= 0.018) {
        continue;
      }
      let side = (i + level) % 2 === 0 ? -1 : 1;
      if (distortion > 0.55 && leafNoise > 0.58) {
        side *= -1;
      }
      const tangentPull = distortion * (leafNoise - 0.5) * 0.72;
      const dirX = normalX * side + tangentX / tangentLength * tangentPull;
      const dirY = normalY * side + tangentY / tangentLength * tangentPull;
      const dust = this.clamp((traits.coarseDust * 0.82 + traits.pollutionPressure * 0.12) *
        (0.52 + leafNoise * 0.92));
      const bleach = this.clamp((traits.ozoneBleach * 0.88 + traits.carbonStagnation * 0.12) *
        (0.56 + this.noise(genome.seed, nodeId * 109 + i * 17) * 0.82));
      const edgeBurn = this.clamp((traits.sulfurAcid * 0.74 + traits.ozoneBleach * 0.30) *
        (0.52 + this.noise(genome.seed, nodeId * 113 + i * 19) * 0.88));
      const damage = this.clamp((distortion * 0.42 + traits.pollutionPressure * 0.18 +
        dust * 0.40 + bleach * 0.34 + edgeBurn * 0.34) * (0.66 + leafNoise * 0.86));
      const leafHealth = this.clamp(traits.leafHealth + branchHealth * 0.24 - damage * 0.34 +
        (leafNoise - 0.5) * 0.12 - traits.carbonStagnation * 0.08, 0.04, 1);
      const length = (9 + maturity * 36 + traits.leafDensity * 12) * (0.72 + (1 - progress) * 0.24) *
        (0.50 + presence * 0.50) * (0.72 + leafHealth * 0.28) * (1 - damage * 0.22 - dust * 0.10);
      const width = (3.0 + maturity * 7.2) * (0.54 + presence * 0.46) * (1 - damage * 0.12 - dust * 0.10);
      const alpha = this.clamp(presence * (0.20 + leafHealth * 0.72) - damage * 0.08 -
        traits.carbonStagnation * 0.06);
      if (alpha <= 0.025) {
        continue;
      }
      result.leaves.push({
        rootX: x,
        rootY: y,
        dirX,
        dirY,
        length,
        width,
        color: damage > 0.58 ? result.palette.leafShadow :
          (damage > 0.34 && leafNoise > 0.38 ? result.palette.leafAccent : result.palette.leaf),
        alpha,
        damage,
        presence,
        health: leafHealth,
        dust,
        bleach,
        edgeBurn
      });
    }
  }

  private buildPalette(plant: PlantState, genome: PlantGenome, traits: PlantVisualTraits): PlantPalette {
    const colorShift = traits.colorShift;
    const vitality = traits.colorVitality;
    const leafHue = this.wrapHue(genome.primaryHue + traits.ozoneBleach * 54 -
      traits.sulfurAcid * 24 - colorShift * 36);
    const accentHue = this.wrapHue(genome.secondaryHue + colorShift * 72 + traits.sulfurAcid * 58);
    const stemHue = this.wrapHue(leafHue + genome.stemHueOffset - colorShift * 14 - traits.nitrogenTwist * 10);
    const leafSaturation = this.clamp(0.36 + vitality * 0.40 - colorShift * 0.28 -
      traits.ozoneBleach * 0.20 - traits.carbonStagnation * 0.16, 0.08, 0.82);
    const leafLight = this.clamp(0.31 + vitality * 0.24 + traits.ozoneBleach * 0.08 -
      colorShift * 0.11 - traits.carbonStagnation * 0.06, 0.20, 0.64);
    const accentSaturation = this.clamp(leafSaturation * (0.72 - colorShift * 0.12) +
      traits.sulfurAcid * 0.08, 0.08, 0.66);
    const accentLight = this.clamp(leafLight - 0.08 - colorShift * 0.03 + traits.sulfurAcid * 0.04, 0.18, 0.50);
    const backgroundSat = this.clamp(0.18 - colorShift * 0.06 - traits.fineHaze * 0.08, 0.04, 0.20);
    const backgroundLight = this.clamp(0.92 - colorShift * 0.05 - traits.fineHaze * 0.08 -
      traits.coarseDust * 0.03, 0.80, 0.94);

    return {
      background: this.hslString(leafHue, backgroundSat, backgroundLight),
      stem: this.hslString(stemHue, this.clamp(leafSaturation * 0.72, 0.12, 0.52), this.clamp(leafLight - 0.12, 0.18, 0.38)),
      stemDark: this.hslString(stemHue, this.clamp(leafSaturation * 0.80, 0.16, 0.58), this.clamp(leafLight - 0.20, 0.14, 0.30)),
      leaf: this.hslString(leafHue, leafSaturation, leafLight),
      leafAccent: this.hslString(accentHue, accentSaturation, accentLight),
      leafShadow: this.hslString(leafHue, this.clamp(leafSaturation * 0.62, 0.10, 0.44), this.clamp(leafLight - 0.15, 0.16, 0.34)),
      bloom: this.hslString(genome.bloomHue, this.clamp(0.46 + vitality * 0.28 - colorShift * 0.16, 0.18, 0.74),
        this.clamp(0.46 + vitality * 0.16, 0.32, 0.64)),
      lesion: this.hslString(18 + traits.ozoneBleach * 34 + traits.sulfurAcid * 42,
        this.clamp(0.34 + colorShift * 0.28 + traits.sulfurAcid * 0.16, 0.28, 0.82),
        this.clamp(0.28 + colorShift * 0.07 + traits.sulfurAcid * 0.05, 0.24, 0.46)),
      soil: this.hslString(26 + colorShift * 12, 0.30, 0.45 - colorShift * 0.05),
      soilDark: this.hslString(28 + colorShift * 10, 0.28, 0.25 - colorShift * 0.03),
      particle: traits.coarseDust > traits.fineHaze ? '#766F62' : (colorShift > 0.48 ? '#5F5C58' : '#6C716C')
    };
  }

  private getSideSlotCount(level: number): number {
    if (level <= 1) {
      return 2;
    }
    if (level === 2) {
      return 1;
    }
    return 0;
  }

  private smoothstep(edge0: number, edge1: number, value: number): number {
    if (edge0 === edge1) {
      return value < edge0 ? 0 : 1;
    }
    const progress = this.clamp((value - edge0) / (edge1 - edge0));
    return progress * progress * (3 - 2 * progress);
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
