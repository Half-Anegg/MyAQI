import { PlantGenome, PlantMemory, PlantState, PlantVisualTraits } from '../models/AqiModels';
import { getPlantMaturity, normalizePlantState } from './PlantAlgorithm';

export class PlantTraitService {
  buildTraits(plantInput: PlantState, genome: PlantGenome): PlantVisualTraits {
    const plant = normalizePlantState(plantInput);
    const memory = plant.pollutantMemory;
    const maturity = getPlantMaturity(plant);
    const pollutantPressure = this.getPollutantShapePressure(memory);
    const pollutionPressure = this.clamp(plant.averageStress * 0.58 + pollutantPressure * 0.42);
    const fineHaze = this.getSignature(memory.pm25, plant.averageStress);
    const coarseDust = this.getSignature(memory.pm10, plant.averageStress);
    const ozoneBleach = this.getSignature(memory.o3, plant.averageStress);
    const nitrogenTwist = this.getSignature(memory.no2, plant.averageStress);
    const sulfurAcid = this.getSignature(memory.so2, plant.averageStress);
    const carbonStagnation = this.getSignature(memory.co, plant.averageStress);
    const sensitivity = 0.86 + genome.alienSensitivity * 0.34;
    const distortion = this.clamp((pollutionPressure - 0.14) * 1.56 * sensitivity +
      coarseDust * 0.10 + ozoneBleach * 0.08 + nitrogenTwist * 0.34);
    const health = this.clamp(1 - pollutionPressure * 0.70 - distortion * 0.12 -
      carbonStagnation * 0.18 - sulfurAcid * 0.08, 0.05, 1);
    const leafHealth = this.clamp(health - coarseDust * 0.30 - ozoneBleach * 0.15 -
      sulfurAcid * 0.14 - distortion * 0.14, 0.04, 1);
    const branchHealth = this.clamp(health - fineHaze * 0.12 - nitrogenTwist * 0.22 -
      carbonStagnation * 0.12 - distortion * 0.10, 0.06, 1);
    const colorShift = this.clamp((pollutionPressure * 0.48 + ozoneBleach * 0.34 +
      sulfurAcid * 0.16 + coarseDust * 0.08 + carbonStagnation * 0.08) *
      genome.colorShiftSensitivity);
    const sway = this.clamp(0.14 + health * 0.72 - carbonStagnation * 0.34 -
      nitrogenTwist * 0.10 - pollutionPressure * 0.12, 0.08, 1);

    return {
      maturity,
      averageStress: plant.averageStress,
      pollutionPressure,
      height: this.clamp(0.34 + maturity * 0.58 + branchHealth * 0.22 - fineHaze * 0.24 -
        carbonStagnation * 0.08 - distortion * 0.12, 0.22, 1),
      leafDensity: this.clamp(0.24 + maturity * 0.46 + leafHealth * 0.32 - coarseDust * 0.34 -
        sulfurAcid * 0.10 - distortion * 0.18, 0.08, 1),
      colorVitality: this.clamp(0.22 + health * 0.66 - ozoneBleach * 0.28 - sulfurAcid * 0.10 -
        carbonStagnation * 0.12 - colorShift * 0.14, 0.06, 1),
      droop: this.clamp(0.04 + pollutionPressure * 0.54 + fineHaze * 0.34 + carbonStagnation * 0.12 +
        distortion * 0.16, 0, 1),
      bloom: this.clamp(0.06 + maturity * 0.48 + health * 0.30 - pollutionPressure * 0.34 -
        sulfurAcid * 0.42 - distortion * 0.14, 0, 1),
      particles: this.clamp(0.06 + pollutionPressure * 0.58 + fineHaze * 0.26 + coarseDust * 0.30, 0, 1),
      distortion,
      health,
      branchPresence: this.clamp(0.22 + maturity * 0.72 + branchHealth * 0.22 - distortion * 0.20, 0.08, 1),
      leafPresence: this.clamp(0.18 + maturity * 0.64 + leafHealth * 0.28 - coarseDust * 0.30 -
        sulfurAcid * 0.08 - distortion * 0.18, 0.04, 1),
      branchHealth,
      leafHealth,
      colorShift,
      fineHaze,
      coarseDust,
      ozoneBleach,
      nitrogenTwist,
      sulfurAcid,
      carbonStagnation,
      sway
    };
  }

  private getPollutantShapePressure(memory: PlantMemory): number {
    return this.clamp(memory.pm25 * 0.26 + memory.pm10 * 0.22 + memory.o3 * 0.18 +
      memory.no2 * 0.16 + memory.so2 * 0.09 + memory.co * 0.09);
  }

  private getSignature(value: number, averageStress: number): number {
    const thresholded = this.smoothstep(0.18, 0.74, value);
    const relativePeak = Math.max(0, value - averageStress);
    return this.clamp(value * 0.54 + thresholded * 0.28 + relativePeak * 1.45);
  }

  private smoothstep(edge0: number, edge1: number, value: number): number {
    if (edge0 === edge1) {
      return value < edge0 ? 0 : 1;
    }
    const progress = this.clamp((value - edge0) / (edge1 - edge0));
    return progress * progress * (3 - 2 * progress);
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
