import { describe, it, expect } from '@ohos/hypium';
import { AqiClient } from '../main/ets/services/AqiClient';
import { PlantState, createInitialPlantState } from '../main/ets/models/AqiModels';
import {
  buildPollutantItems,
  getPlantGrowthDays,
  getPlantMaturity,
  normalizePlantState,
  normalizePollutantIndex,
  updatePlantWithSnapshot
} from '../main/ets/services/PlantAlgorithm';
import { PlantMorphologyService } from '../main/ets/services/PlantMorphologyService';

export default function localUnitTest() {
  describe('AQI electronic plant', () => {
    it('parses normal WAQI response', 0, () => {
      const client = new AqiClient();
      const snapshot = client.parseResponse({
        status: 'ok',
        data: {
          aqi: 82,
          dominentpol: 'pm25',
          city: {
            name: 'Beijing, China',
            url: 'https://aqicn.org/city/beijing/'
          },
          time: {
            iso: '2026-05-01T12:00:00+08:00'
          },
          iaqi: {
            pm25: { v: 96 },
            pm10: { v: 70 },
            o3: { v: 40 },
            no2: { v: 35 },
            so2: { v: 8 },
            co: { v: 5 }
          }
        }
      }, '北京');

      expect(snapshot.cityName).assertEqual('Beijing');
      expect(snapshot.aqi).assertEqual(82);
      expect(snapshot.qualityLabel).assertEqual('良');
      expect(snapshot.pollutants.pm25).assertEqual(96);
      expect(snapshot.missingPollutants.length).assertEqual(0);
    });

    it('reports missing pollutant fields', 0, () => {
      const client = new AqiClient();
      const snapshot = client.parseResponse({
        status: 'ok',
        data: {
          aqi: '42',
          city: {
            name: 'Shanghai, China'
          },
          time: {
            s: '2026-05-01 10:00:00'
          },
          iaqi: {
            pm25: { v: 42 }
          }
        }
      }, '上海');

      expect(snapshot.pollutants.pm25).assertEqual(42);
      expect(snapshot.pollutants.pm10).assertEqual(null);
      expect(snapshot.missingPollutants.length).assertEqual(5);
    });

    it('normalizes locations to city level', 0, () => {
      const client = new AqiClient();
      expect(client.normalizeCityName('北京市朝阳区')).assertEqual('北京市');
      expect(client.normalizeCityName('北京')).assertEqual('北京市');
      expect(client.normalizeCityName('成都, 四川')).assertEqual('成都市');
      expect(client.normalizeCityName('Xizhimen, Beijing, China')).assertEqual('Beijing');
    });

    it('rejects non-ok WAQI response', 0, () => {
      const client = new AqiClient();
      let failed = false;
      try {
        client.parseResponse({
          status: 'error',
          data: 'Unknown station'
        }, '不存在的城市');
      } catch (error) {
        failed = true;
      }
      expect(failed).assertTrue();
    });

    it('does not update plant twice for the same timestamp', 0, () => {
      const client = new AqiClient();
      const snapshot = client.parseResponse({
        status: 'ok',
        data: {
          aqi: 135,
          city: {
            name: 'Chengdu, China'
          },
          time: {
            iso: '2026-05-01T09:00:00+08:00'
          },
          iaqi: {
            pm25: { v: 145 },
            pm10: { v: 120 },
            o3: { v: 70 },
            no2: { v: 68 },
            so2: { v: 20 },
            co: { v: 12 }
          }
        }
      }, '成都');

      const first = updatePlantWithSnapshot(createInitialPlantState(snapshot.cityKey, snapshot.cityName), snapshot);
      const second = updatePlantWithSnapshot(first, snapshot);
      expect(second.sampleCount).assertEqual(first.sampleCount);
      expect(second.averageStress).assertEqual(first.averageStress);
    });

    it('uses unique observation days for plant maturity', 0, () => {
      const client = new AqiClient();
      const firstDayMorning = client.parseResponse({
        status: 'ok',
        data: {
          aqi: 68,
          city: { name: 'Hangzhou, China' },
          time: { iso: '2026-05-01T08:00:00+08:00' },
          iaqi: {
            pm25: { v: 62 },
            pm10: { v: 50 },
            o3: { v: 32 },
            no2: { v: 26 },
            so2: { v: 8 },
            co: { v: 4 }
          }
        }
      }, '杭州');
      const firstDayAfternoon = client.parseResponse({
        status: 'ok',
        data: {
          aqi: 72,
          city: { name: 'Hangzhou, China' },
          time: { iso: '2026-05-01T16:00:00+08:00' },
          iaqi: {
            pm25: { v: 70 },
            pm10: { v: 56 },
            o3: { v: 48 },
            no2: { v: 30 },
            so2: { v: 10 },
            co: { v: 5 }
          }
        }
      }, '杭州');
      const secondDay = client.parseResponse({
        status: 'ok',
        data: {
          aqi: 76,
          city: { name: 'Hangzhou, China' },
          time: { iso: '2026-05-02T08:00:00+08:00' },
          iaqi: {
            pm25: { v: 74 },
            pm10: { v: 60 },
            o3: { v: 45 },
            no2: { v: 32 },
            so2: { v: 10 },
            co: { v: 5 }
          }
        }
      }, '杭州');

      const initial = createInitialPlantState(firstDayMorning.cityKey, firstDayMorning.cityName);
      const one = updatePlantWithSnapshot(initial, firstDayMorning);
      const sameDay = updatePlantWithSnapshot(one, firstDayAfternoon);
      const two = updatePlantWithSnapshot(sameDay, secondDay);

      expect(one.sampleCount).assertEqual(1);
      expect(sameDay.sampleCount).assertEqual(2);
      expect(getPlantGrowthDays(sameDay)).assertEqual(1);
      expect(getPlantGrowthDays(two)).assertEqual(2);
      expect(getPlantMaturity(one) < 0.2).assertTrue();
    });

    it('keeps legacy stored plant states from crashing growth helpers', 0, () => {
      const legacyPlant = JSON.parse('{"cityKey":"legacy","cityName":"旧城市","lastObservedAt":"2026-05-01T08:00:00+08:00","sampleCount":1,"averageStress":0.22,"pollutantMemory":{"pm25":0.28,"pm10":0.24,"o3":0.22,"no2":0.2,"so2":0.16,"co":0.14},"heightScore":0.78,"leafScore":0.72,"colorScore":0.76,"droopScore":0.16,"bloomScore":0.42,"particleScore":0.16,"updatedAt":"2026-05-01T08:01:00+08:00"}') as PlantState;
      const normalized = normalizePlantState(legacyPlant);
      expect(getPlantGrowthDays(legacyPlant)).assertEqual(1);
      expect(normalized.observationDates.length).assertEqual(1);
      expect(normalized.observationDates[0]).assertEqual('2026-05-01');
      expect(normalized.genomeSeed).assertEqual('');
    });

    it('updates different cities as separate plant states', 0, () => {
      const client = new AqiClient();
      const beijing = client.parseResponse({
        status: 'ok',
        data: {
          aqi: 58,
          city: { name: 'Beijing, China' },
          time: { iso: '2026-05-01T08:00:00+08:00' },
          iaqi: {
            pm25: { v: 55 },
            pm10: { v: 48 },
            o3: { v: 30 },
            no2: { v: 24 },
            so2: { v: 6 },
            co: { v: 4 }
          }
        }
      }, '北京');
      const guangzhou = client.parseResponse({
        status: 'ok',
        data: {
          aqi: 170,
          city: { name: 'Guangzhou, China' },
          time: { iso: '2026-05-01T08:00:00+08:00' },
          iaqi: {
            pm25: { v: 170 },
            pm10: { v: 138 },
            o3: { v: 118 },
            no2: { v: 92 },
            so2: { v: 30 },
            co: { v: 18 }
          }
        }
      }, '广州');

      const beijingPlant = updatePlantWithSnapshot(createInitialPlantState(beijing.cityKey, beijing.cityName), beijing);
      const guangzhouPlant =
        updatePlantWithSnapshot(createInitialPlantState(guangzhou.cityKey, guangzhou.cityName), guangzhou);
      expect(beijingPlant.cityKey).assertEqual('beijing');
      expect(guangzhouPlant.cityKey).assertEqual('guangzhou');
      expect(guangzhouPlant.averageStress > beijingPlant.averageStress).assertTrue();
    });

    it('normalizes severe pollutant values as higher stress', 0, () => {
      const calm = normalizePollutantIndex(40);
      const severe = normalizePollutantIndex(260);
      expect(severe > calm).assertTrue();
    });

    it('marks missing pollutant display items', 0, () => {
      const plant = createInitialPlantState('preview', '空气花园');
      const items = buildPollutantItems(null, plant.pollutantMemory);
      expect(items.length).assertEqual(6);
      expect(items[0].missing).assertTrue();
    });

    it('generates stable plant genome from user seed and city key', 0, () => {
      const service = new PlantMorphologyService();
      const first = service.buildGenome('seed_a', 'beijing');
      const second = service.buildGenome('seed_a', 'beijing');
      const changed = service.buildGenome('seed_b', 'beijing');
      expect(first.primaryHue).assertEqual(second.primaryHue);
      expect(first.branchAngle).assertEqual(second.branchAngle);
      expect(first.primaryHue !== changed.primaryHue || first.branchAngle !== changed.branchAngle).assertTrue();
      const visibleDelta = Math.abs(first.primaryHue - changed.primaryHue) +
        Math.abs(first.branchAngle - changed.branchAngle) * 80 +
        Math.abs(first.leafRhythm - changed.leafRhythm) * 40 +
        Math.abs(first.curl - changed.curl) * 30;
      expect(visibleDelta > 12).assertTrue();
    });

    it('makes polluted plants more distorted and color shifted', 0, () => {
      const service = new PlantMorphologyService();
      const clean = createInitialPlantState('test', '测试市');
      clean.averageStress = 0.16;
      clean.pollutantMemory.pm25 = 0.10;
      clean.pollutantMemory.pm10 = 0.12;
      clean.pollutantMemory.o3 = 0.12;
      clean.pollutantMemory.no2 = 0.10;
      clean.pollutantMemory.so2 = 0.08;
      clean.pollutantMemory.co = 0.08;

      const polluted = createInitialPlantState('test', '测试市');
      polluted.averageStress = 0.82;
      polluted.pollutantMemory.pm25 = 0.86;
      polluted.pollutantMemory.pm10 = 0.78;
      polluted.pollutantMemory.o3 = 0.74;
      polluted.pollutantMemory.no2 = 0.70;
      polluted.pollutantMemory.so2 = 0.62;
      polluted.pollutantMemory.co = 0.58;

      const genome = service.buildGenome('seed_a', 'test');
      expect(service.getDistortionScore(polluted, genome) > service.getDistortionScore(clean, genome)).assertTrue();
      expect(service.getColorPollutionShift(polluted, genome) > service.getColorPollutionShift(clean, genome)).assertTrue();
    });

    it('increases L-System complexity as plant matures', 0, () => {
      const service = new PlantMorphologyService();
      const seedling = createInitialPlantState('growth', '成长市');
      seedling.observationDates = ['2026-05-01'];

      const mature = createInitialPlantState('growth', '成长市');
      mature.observationDates = [
        '2026-05-01',
        '2026-05-02',
        '2026-05-03',
        '2026-05-04',
        '2026-05-05',
        '2026-05-06',
        '2026-05-07'
      ];

      const seedlingMorphology = service.buildMorphology(seedling, 'seed_a', 360, 720, 0, 0, 0, 0);
      const matureMorphology = service.buildMorphology(mature, 'seed_a', 360, 720, 0, 0, 0, 0);
      expect(matureMorphology.branches.length > seedlingMorphology.branches.length).assertTrue();
      expect(matureMorphology.leaves.length > seedlingMorphology.leaves.length).assertTrue();
    });
  });
}
