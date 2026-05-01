import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { PlantState, StoredCityRecord, createInitialPlantState } from '../models/AqiModels';
import { normalizePlantState } from '../services/PlantAlgorithm';

const STORE_NAME: string = 'aqi_plant_store';
const RECORDS_KEY: string = 'city_records';
const RECORD_ORDER_KEY: string = 'city_record_order';
const LAST_CITY_KEY: string = 'last_city_key';
const INSTALL_SEED_KEY: string = 'install_seed';

export class PlantStore {
  private store: preferences.Preferences | null = null;

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.store !== null) {
      return;
    }
    try {
      this.store = await preferences.getPreferences(context, STORE_NAME);
    } catch (error) {
      throw new Error('本地存储初始化失败');
    }
  }

  async getLastCityKey(): Promise<string> {
    const pref = this.requireStore();
    try {
      const value = await pref.get(LAST_CITY_KEY, '');
      return String(value);
    } catch (error) {
      return '';
    }
  }

  async saveLastCityKey(cityKey: string): Promise<void> {
    const pref = this.requireStore();
    try {
      await pref.put(LAST_CITY_KEY, cityKey);
      await pref.flush();
    } catch (error) {
      throw new Error('保存当前城市失败');
    }
  }

  async getInstallSeed(): Promise<string> {
    const pref = this.requireStore();
    try {
      const value = String(await pref.get(INSTALL_SEED_KEY, ''));
      if (value.length > 0) {
        return value;
      }
      return await this.regenerateInstallSeed();
    } catch (error) {
      return await this.regenerateInstallSeed();
    }
  }

  async regenerateInstallSeed(): Promise<string> {
    const pref = this.requireStore();
    const seed = this.createInstallSeed();
    try {
      await pref.put(INSTALL_SEED_KEY, seed);
      await pref.flush();
      return seed;
    } catch (error) {
      throw new Error('重新生成植物种子失败');
    }
  }

  async getCityRecord(cityKey: string): Promise<StoredCityRecord | null> {
    const records = await this.readRecords();
    const record = records[cityKey];
    if (record === undefined || record === null) {
      return null;
    }
    return this.normalizeRecord(record);
  }

  async getAllCityRecords(): Promise<StoredCityRecord[]> {
    const records = await this.readRecords();
    const orderedKeys = await this.readRecordOrder();
    const keys = this.mergeRecordKeys(Object.keys(records), orderedKeys);
    const result: StoredCityRecord[] = [];
    for (let i = 0; i < keys.length; i++) {
      const record = records[keys[i]];
      if (record !== undefined && record !== null) {
        result.push(this.normalizeRecord(record));
      }
    }
    return result;
  }

  async saveCityRecord(record: StoredCityRecord): Promise<void> {
    const pref = this.requireStore();
    const records = await this.readRecords();
    const order = await this.readRecordOrder();
    const installSeed = await this.getInstallSeed();
    const normalizedPlant = normalizePlantState(record.plant);
    normalizedPlant.genomeSeed = installSeed;
    records[record.cityKey] = {
      cityKey: record.cityKey,
      cityName: record.cityName,
      snapshot: record.snapshot,
      plant: normalizedPlant
    };
    if (!order.includes(record.cityKey)) {
      order.push(record.cityKey);
    }
    try {
      await pref.put(RECORDS_KEY, JSON.stringify(records));
      await pref.put(RECORD_ORDER_KEY, JSON.stringify(order));
      await pref.flush();
      await this.saveLastCityKey(record.cityKey);
    } catch (error) {
      throw new Error('保存植物状态失败');
    }
  }

  async getStoredPlant(cityKey: string): Promise<PlantState | null> {
    const record = await this.getCityRecord(cityKey);
    return record === null ? null : record.plant;
  }

  private async readRecords(): Promise<Record<string, StoredCityRecord>> {
    const pref = this.requireStore();
    let value = '{}';
    try {
      value = String(await pref.get(RECORDS_KEY, '{}'));
    } catch (error) {
      return {};
    }
    try {
      return JSON.parse(value) as Record<string, StoredCityRecord>;
    } catch (error) {
      return {};
    }
  }

  private async readRecordOrder(): Promise<string[]> {
    const pref = this.requireStore();
    let value = '[]';
    try {
      value = String(await pref.get(RECORD_ORDER_KEY, '[]'));
    } catch (error) {
      return [];
    }
    try {
      const parsed = JSON.parse(value) as string[];
      if (parsed === undefined || parsed === null || !Array.isArray(parsed)) {
        return [];
      }
      const order: string[] = [];
      for (let i = 0; i < parsed.length; i++) {
        const key = String(parsed[i]);
        if (key.length > 0) {
          order.push(key);
        }
      }
      return order;
    } catch (error) {
      return [];
    }
  }

  private mergeRecordKeys(allKeys: string[], orderedKeys: string[]): string[] {
    const result: string[] = [];
    for (let i = 0; i < orderedKeys.length; i++) {
      if (allKeys.includes(orderedKeys[i]) && !result.includes(orderedKeys[i])) {
        result.push(orderedKeys[i]);
      }
    }
    const sortedKeys = allKeys.sort();
    for (let i = 0; i < sortedKeys.length; i++) {
      if (!result.includes(sortedKeys[i])) {
        result.push(sortedKeys[i]);
      }
    }
    return result;
  }

  private normalizeRecord(record: StoredCityRecord): StoredCityRecord {
    const cityKey = record.cityKey === undefined || record.cityKey === null ? 'unknown' : record.cityKey;
    const cityName = record.cityName === undefined || record.cityName === null ? '未知城市' : record.cityName;
    const plant = record.plant === undefined || record.plant === null ?
      createInitialPlantState(cityKey, cityName) : normalizePlantState(record.plant);
    return {
      cityKey,
      cityName,
      snapshot: record.snapshot,
      plant
    };
  }

  private createInstallSeed(): string {
    const timestamp = new Date().getTime();
    const randomPart = Math.floor(Math.random() * 1000000000);
    return `seed_${timestamp}_${randomPart}`;
  }

  private requireStore(): preferences.Preferences {
    if (this.store === null) {
      throw new Error('本地存储尚未初始化');
    }
    return this.store;
  }
}
