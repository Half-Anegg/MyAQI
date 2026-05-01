import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { PlantState, StoredCityRecord, createInitialPlantState } from '../models/AqiModels';
import { normalizePlantState } from '../services/PlantAlgorithm';

const STORE_NAME: string = 'aqi_plant_store';
const RECORDS_KEY: string = 'city_records';
const LAST_CITY_KEY: string = 'last_city_key';

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

  async getCityRecord(cityKey: string): Promise<StoredCityRecord | null> {
    const records = await this.readRecords();
    const record = records[cityKey];
    if (record === undefined || record === null) {
      return null;
    }
    return this.normalizeRecord(record);
  }

  async saveCityRecord(record: StoredCityRecord): Promise<void> {
    const pref = this.requireStore();
    const records = await this.readRecords();
    records[record.cityKey] = record;
    try {
      await pref.put(RECORDS_KEY, JSON.stringify(records));
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

  private requireStore(): preferences.Preferences {
    if (this.store === null) {
      throw new Error('本地存储尚未初始化');
    }
    return this.store;
  }
}
