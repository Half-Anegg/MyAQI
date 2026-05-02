import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { AqiSnapshot, PlantState, PollutantDisplayItem, PollutantVector, StoredCityRecord, createInitialPlantState } from '../models/AqiModels';
import { AqiClient } from '../services/AqiClient';
import { LocationService } from '../services/LocationService';
import { MockAqiService } from '../services/MockAqiService';
import { MorphBranch, MorphBud, MorphLeaf, PlantMorphology, PlantMorphologyService } from '../services/PlantMorphologyService';
import {
  buildPollutantItems,
  getPlantGrowthDays,
  PLANT_MATURITY_DAYS,
  getQualityColor,
  normalizePlantState,
  updatePlantWithSnapshot
} from '../services/PlantAlgorithm';
import { PlantStore } from '../storage/PlantStore';

const PREVIEW_CITY_KEY: string = 'preview';
const PREVIEW_CITY_NAME: string = '空气花园';
const DEFAULT_CANVAS_WIDTH: number = 320;
const CANVAS_HEIGHT: number = 760;
const PLANT_ANIMATION_INTERVAL: number = 16;
const PLANT_DETAIL_SHIFT: number = 390;
const DETAIL_PANEL_HEIGHT: number = 356;
const LEAF_BURST_DURATION: number = 72;

@Entry
@Component
struct Index {
  private aqiClient: AqiClient = new AqiClient();
  private locationService: LocationService = new LocationService();
  private mockAqiService: MockAqiService = new MockAqiService();
  private plantMorphologyService: PlantMorphologyService = new PlantMorphologyService();
  private plantStore: PlantStore = new PlantStore();
  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);
  private canvasReady: boolean = false;
  private animationTimer: number = -1;
  private animationFrame: number = 0;
  private touchPulse: number = 0;
  private plantSlideProgress: number = 1;
  private plantSlideDirection: number = 1;
  private plantDragOffsetX: number = 0;
  private plantDragTargetIndex: number = -1;
  private plantDragReturning: boolean = false;
  private transitionPreviousPlant: PlantState | null = null;
  private storeReady: boolean = false;
  private preparing: boolean = false;
  private detailLayoutTarget: number = 0;
  private installSeed: string = 'preview_seed';
  private interactionActive: boolean = false;
  private leafBurstActive: boolean = false;
  private leafBurstFrame: number = 0;

  @State cityInput: string = '北京';
  @State loading: boolean = false;
  @State statusText: string = '正在准备空气花园';
  @State @Watch('onDataModelChanged') currentSnapshot: AqiSnapshot | null = null;
  @State @Watch('onDataModelChanged') currentPlant: PlantState = createInitialPlantState(PREVIEW_CITY_KEY, PREVIEW_CITY_NAME);
  @State canvasWidth: number = DEFAULT_CANVAS_WIDTH;
  @State canvasHeight: number = CANVAS_HEIGHT;
  @State uiRevision: number = 0;
  @State displayCityName: string = '未选择城市';
  @State displayAqiText: string = '--';
  @State displayQualityText: string = '等待数据';
  @State displayObservedText: string = '暂无更新时间';
  @State displayDominantText: string = '主要污染物 暂无';
  @State displayMissingText: string = '';
  @State displaySourceText: string = '数据来源：WAQI，当前仅用于免费非商业演示。';
  @State displayGrowthText: string = '等待第一天数据';
  @State lastFetchText: string = '尚未刷新';
  @State cityRecords: StoredCityRecord[] = [];
  @State currentCityIndex: number = 0;
  @State detailLayoutProgress: number = 0;
  @State testEditorExpanded: boolean = false;
  @State testPm25Text: string = '35';
  @State testPm10Text: string = '45';
  @State testO3Text: string = '50';
  @State testNo2Text: string = '28';
  @State testSo2Text: string = '8';
  @State testCoText: string = '4';
  @State pollutantItems: PollutantDisplayItem[] =
    buildPollutantItems(null, createInitialPlantState(PREVIEW_CITY_KEY, PREVIEW_CITY_NAME).pollutantMemory);

  aboutToAppear(): void {
    this.startPlantAnimation();
    this.prepareApp();
  }

  aboutToDisappear(): void {
    this.stopPlantAnimation();
  }

  onPageShow(): void {
    if (!this.storeReady || this.preparing) {
      return;
    }
    this.syncSelectedCityFromStore();
  }

  private startPlantAnimation(): void {
    if (this.animationTimer >= 0) {
      return;
    }
    this.animationTimer = setInterval(() => {
      this.animationFrame += 1;
      if (this.interactionActive) {
        if (this.touchPulse > 0) {
          this.touchPulse = Math.max(0, this.touchPulse - (this.leafBurstActive ? 0.020 : 0.035));
        }
        if (this.leafBurstActive) {
          this.leafBurstFrame += 1;
        }
        if (this.touchPulse <= 0 && (!this.leafBurstActive || this.leafBurstFrame >= LEAF_BURST_DURATION)) {
          this.interactionActive = false;
          this.leafBurstActive = false;
          this.leafBurstFrame = 0;
        }
      }
      if (this.plantSlideProgress < 1) {
        this.plantSlideProgress = Math.min(1, this.plantSlideProgress + 0.055);
        if (this.plantSlideProgress >= 1) {
          this.transitionPreviousPlant = null;
        }
      }
      if (this.plantDragReturning) {
        this.plantDragOffsetX *= 0.68;
        if (Math.abs(this.plantDragOffsetX) < 1) {
          this.plantDragOffsetX = 0;
          this.plantDragTargetIndex = -1;
          this.plantDragReturning = false;
        }
      }
      if (Math.abs(this.detailLayoutProgress - this.detailLayoutTarget) > 0.01) {
        if (this.detailLayoutProgress < this.detailLayoutTarget) {
          this.detailLayoutProgress = Math.min(this.detailLayoutTarget, this.detailLayoutProgress + 0.075);
        } else {
          this.detailLayoutProgress = Math.max(this.detailLayoutTarget, this.detailLayoutProgress - 0.075);
        }
      }
      this.drawPlant();
    }, PLANT_ANIMATION_INTERVAL);
  }

  private stopPlantAnimation(): void {
    if (this.animationTimer < 0) {
      return;
    }
    clearInterval(this.animationTimer);
    this.animationTimer = -1;
  }

  onDataModelChanged(changedProperty: string): void {
    if (changedProperty === '__unused__') {
      return;
    }
    this.rebuildDisplayState();
    this.requestRedraw();
  }

  private rebuildDisplayState(): void {
    const snapshot = this.currentSnapshot;
    const plant = normalizePlantState(this.currentPlant);
    this.displayCityName = snapshot === null ? '未选择城市' : snapshot.cityName;
    this.displayAqiText = snapshot === null || snapshot.aqi === null ? '--' : Math.round(snapshot.aqi).toString();
    this.displayQualityText = snapshot === null ? '等待数据' : snapshot.qualityLabel;
    this.displayObservedText = snapshot === null || snapshot.observedAt.length === 0 ?
      '暂无更新时间' : `更新于 ${snapshot.observedAt}`;
    this.displayDominantText = snapshot === null || snapshot.dominantPollutant.length === 0 ?
      '主要污染物 暂无' : `主要污染物 ${snapshot.dominantPollutant.toUpperCase()}`;
    this.displayMissingText = snapshot === null || snapshot.missingPollutants.length === 0 ?
      '' : `缺失 ${snapshot.missingPollutants.join('、')}，对应植物参数沿用上一状态`;
    this.displaySourceText = snapshot === null ?
      '数据来源：WAQI，当前仅用于免费非商业演示。' :
      `数据来源：${snapshot.sourceName}，当前仅用于免费非商业演示。`;
    this.displayGrowthText = this.makeGrowthText(plant);
    this.pollutantItems = buildPollutantItems(snapshot === null ? null : snapshot.pollutants, plant.pollutantMemory);
    this.uiRevision += 1;
  }

  private cloneSnapshot(snapshot: AqiSnapshot): AqiSnapshot {
    return {
      cityKey: snapshot.cityKey,
      cityName: snapshot.cityName,
      stationName: snapshot.stationName,
      aqi: snapshot.aqi,
      qualityLabel: snapshot.qualityLabel,
      dominantPollutant: snapshot.dominantPollutant,
      observedAt: snapshot.observedAt,
      sourceName: snapshot.sourceName,
      sourceUrl: snapshot.sourceUrl,
      pollutants: {
        pm25: snapshot.pollutants.pm25,
        pm10: snapshot.pollutants.pm10,
        o3: snapshot.pollutants.o3,
        no2: snapshot.pollutants.no2,
        so2: snapshot.pollutants.so2,
        co: snapshot.pollutants.co
      },
      missingPollutants: snapshot.missingPollutants.slice()
    };
  }

  private twoDigits(value: number): string {
    if (value < 10) {
      return `0${value}`;
    }
    return value.toString();
  }

  private formatFetchTime(): string {
    const now = new Date();
    const hour = this.twoDigits(now.getHours());
    const minute = this.twoDigits(now.getMinutes());
    const second = this.twoDigits(now.getSeconds());
    return `本次刷新 ${hour}:${minute}:${second}`;
  }

  private getHourKey(value: string): string {
    if (value.length === 0) {
      return '';
    }
    const date = new Date(value);
    if (isNaN(date.getTime())) {
      return '';
    }
    return `${date.getFullYear()}-${this.twoDigits(date.getMonth() + 1)}-${this.twoDigits(date.getDate())}-${this.twoDigits(date.getHours())}`;
  }

  private getCurrentRecord(): StoredCityRecord | null {
    if (this.currentSnapshot === null) {
      return null;
    }
    if (this.currentCityIndex >= 0 && this.currentCityIndex < this.cityRecords.length &&
      this.cityRecords[this.currentCityIndex].cityKey === this.currentSnapshot.cityKey) {
      return this.cityRecords[this.currentCityIndex];
    }
    for (let i = 0; i < this.cityRecords.length; i++) {
      if (this.cityRecords[i].cityKey === this.currentSnapshot.cityKey) {
        return this.cityRecords[i];
      }
    }
    return null;
  }

  private hasCurrentCityUpdatedThisHour(): boolean {
    const record = this.getCurrentRecord();
    if (record === null || record.lastFetchedAt.length === 0) {
      return false;
    }
    return this.getHourKey(record.lastFetchedAt) === this.getHourKey(new Date().toISOString());
  }

  private shouldRefreshCurrentCityOnTap(): boolean {
    return this.currentSnapshot !== null && !this.isTestCity() && this.aqiClient.hasToken() &&
      !this.hasCurrentCityUpdatedThisHour();
  }

  private hasCityData(): boolean {
    return this.currentSnapshot !== null && this.cityRecords.length > 0;
  }

  private clearCurrentCityState(): void {
    this.currentSnapshot = null;
    this.currentPlant = createInitialPlantState(PREVIEW_CITY_KEY, PREVIEW_CITY_NAME);
    this.currentCityIndex = 0;
    this.cityInput = '';
    this.statusText = '请选择城市，开始培育空气植物';
    this.rebuildDisplayState();
    this.requestRedraw();
  }

  private isTestCityInput(city: string): boolean {
    const normalized = city.trim();
    return normalized === '测试' || normalized.indexOf('测试') >= 0;
  }

  private makeTestCityName(city: string): string {
    const normalized = city.trim();
    if (normalized.length === 0 || normalized === '测试') {
      return '测试市';
    }
    return normalized;
  }

  private async prepareApp(): Promise<void> {
    if (this.preparing) {
      return;
    }
    this.preparing = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await this.plantStore.init(context);
      this.installSeed = await this.plantStore.getInstallSeed();
      this.storeReady = true;
      const hasRecord = await this.reloadStoredRecords(true);
      if (hasRecord) {
        this.statusText = '已载入上次查看的城市';
        return;
      }

      this.clearCurrentCityState();
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    } finally {
      this.preparing = false;
    }
  }

  private async reloadStoredRecords(selectLastCity: boolean): Promise<boolean> {
    const records = await this.plantStore.getAllCityRecords();
    this.cityRecords = records;
    if (records.length === 0) {
      this.currentCityIndex = 0;
      return false;
    }

    let targetKey = this.currentSnapshot === null ? '' : this.currentSnapshot.cityKey;
    if (selectLastCity) {
      const lastCityKey = await this.plantStore.getLastCityKey();
      if (lastCityKey.length > 0) {
        targetKey = lastCityKey;
      }
    }

    const index = this.findRecordIndex(records, targetKey);
    this.applyRecord(records, index < 0 ? 0 : index);
    return true;
  }

  private async syncSelectedCityFromStore(): Promise<void> {
    try {
      this.installSeed = await this.plantStore.getInstallSeed();
      const hasRecords = await this.reloadStoredRecords(true);
      if (!hasRecords) {
        this.clearCurrentCityState();
      }
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    }
  }

  private findRecordIndex(records: StoredCityRecord[], cityKey: string): number {
    if (cityKey.length === 0) {
      return -1;
    }
    for (let i = 0; i < records.length; i++) {
      if (records[i].cityKey === cityKey) {
        return i;
      }
    }
    return -1;
  }

  private applyRecord(records: StoredCityRecord[], index: number, transitionProgress: number = 0): void {
    if (index < 0 || index >= records.length) {
      return;
    }
    const record = records[index];
    if (this.currentSnapshot !== null && this.currentSnapshot.cityKey !== record.cityKey) {
      this.transitionPreviousPlant = normalizePlantState(this.currentPlant);
      this.plantSlideDirection = index > this.currentCityIndex ? -1 : 1;
      this.plantSlideProgress = Math.max(0, Math.min(1, transitionProgress));
    }
    this.currentCityIndex = index;
    this.currentSnapshot = record.snapshot === null ? null : this.cloneSnapshot(record.snapshot);
    this.currentPlant = normalizePlantState(record.plant);
    this.cityInput = record.cityName;
    this.rebuildDisplayState();
    this.requestRedraw();
  }

  private getDragTargetIndex(offsetX: number): number {
    if (offsetX < 0) {
      return this.currentCityIndex + 1;
    }
    if (offsetX > 0) {
      return this.currentCityIndex - 1;
    }
    return -1;
  }

  private getBoundedDragOffset(offsetX: number): number {
    const width = Math.max(280, this.canvasWidth);
    const targetIndex = this.getDragTargetIndex(offsetX);
    const edgeResistance = targetIndex < 0 || targetIndex >= this.cityRecords.length ? 0.28 : 1;
    const resistedOffset = offsetX * edgeResistance;
    if (resistedOffset > width) {
      return width;
    }
    if (resistedOffset < -width) {
      return -width;
    }
    return resistedOffset;
  }

  private handlePlantDragUpdate(offsetX: number): void {
    if (this.cityRecords.length <= 1 || isNaN(offsetX)) {
      return;
    }
    this.transitionPreviousPlant = null;
    this.plantSlideProgress = 1;
    this.plantDragReturning = false;
    this.plantDragOffsetX = this.getBoundedDragOffset(offsetX);
    this.plantDragTargetIndex = this.getDragTargetIndex(this.plantDragOffsetX);
    this.drawPlant();
  }

  private async handlePlantDragEnd(): Promise<void> {
    if (this.cityRecords.length <= 1) {
      this.plantDragOffsetX = 0;
      this.plantDragTargetIndex = -1;
      this.plantDragReturning = false;
      this.requestRedraw();
      return;
    }

    const width = Math.max(280, this.canvasWidth);
    const dragOffset = this.plantDragOffsetX;
    const targetIndex = this.plantDragTargetIndex;
    const shouldSwitch = targetIndex >= 0 && targetIndex < this.cityRecords.length && Math.abs(dragOffset) > width * 0.09;

    if (!shouldSwitch) {
      this.plantDragReturning = true;
      return;
    }

    const dragFraction = Math.max(0.05, Math.min(0.92, Math.abs(dragOffset) / width));
    const progress = 1 - Math.pow(1 - dragFraction, 1 / 3);
    this.plantDragOffsetX = 0;
    this.plantDragTargetIndex = -1;
    this.plantDragReturning = false;
    this.applyRecord(this.cityRecords, targetIndex, progress);
    this.plantSlideDirection = dragOffset < 0 ? -1 : 1;

    try {
      await this.plantStore.saveLastCityKey(this.cityRecords[targetIndex].cityKey);
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    }
  }

  private async searchCity(): Promise<void> {
    if (this.loading) {
      return;
    }
    const city = this.cityInput.trim();
    if (city.length === 0) {
      this.statusText = '请输入城市名称';
      return;
    }
    if (this.isTestCityInput(city)) {
      await this.loadTestCity(city);
      return;
    }
    await this.loadSnapshot(async (): Promise<AqiSnapshot> => {
      return this.aqiClient.fetchByCity(city);
    }, `正在查询 ${city} 的空气质量`);
  }

  private async loadTestCity(cityInput: string): Promise<void> {
    if (this.loading) {
      return;
    }
    const city = this.makeTestCityName(cityInput);
    this.loading = true;
    this.statusText = `正在创建 ${city} 的测试植物`;
    try {
      const snapshot = this.mockAqiService.createSnapshot(city, 0, 'clean');
      const storedPlant = await this.plantStore.getStoredPlant(snapshot.cityKey);
      const nextPlant = updatePlantWithSnapshot(storedPlant, snapshot);
      await this.plantStore.saveCityRecord({
        cityKey: snapshot.cityKey,
        cityName: snapshot.cityName,
        snapshot,
        plant: nextPlant,
        lastFetchedAt: new Date().toISOString()
      });
      this.lastFetchText = this.formatFetchTime();
      await this.reloadStoredRecords(true);
      this.statusText = `已创建 ${snapshot.cityName}，可用测试栏快速累积数据`;
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  private async refreshCurrent(): Promise<void> {
    if (this.currentSnapshot !== null) {
      this.cityInput = this.currentSnapshot.cityName;
    }
    await this.searchCity();
  }

  private async refreshByLocation(): Promise<void> {
    if (this.loading) {
      return;
    }
    await this.loadSnapshot(async (): Promise<AqiSnapshot> => {
      const context = getContext(this) as common.UIAbilityContext;
      const location = await this.locationService.requestApproximateLocation(context);
      if (location.cityName.length > 0) {
        return this.aqiClient.fetchByCity(location.cityName);
      }
      return this.aqiClient.fetchByGeo(location.latitude, location.longitude);
    }, '正在定位当前城市');
  }

  private async loadSnapshot(loader: () => Promise<AqiSnapshot>, loadingText: string): Promise<void> {
    if (!this.aqiClient.hasToken()) {
      this.statusText = '请先在 ApiConfig.ets 中配置 WAQI token';
      return;
    }

    this.loading = true;
    this.statusText = loadingText;
    try {
      const snapshot = await loader();
      const storedPlant = await this.plantStore.getStoredPlant(snapshot.cityKey);
      const repeatedObservation = storedPlant !== null &&
        storedPlant.lastObservedAt === snapshot.observedAt &&
        snapshot.observedAt.length > 0;
      const nextPlant = updatePlantWithSnapshot(storedPlant, snapshot);

      this.currentSnapshot = this.cloneSnapshot(snapshot);
      this.currentPlant = normalizePlantState(nextPlant);
      this.cityInput = snapshot.cityName;
      this.lastFetchText = this.formatFetchTime();
      this.rebuildDisplayState();
      this.statusText = repeatedObservation ? '已是该城市的最新数据，植物状态未重复累计' :
        `植物已吸收这次空气数据，成长 ${getPlantGrowthDays(nextPlant)} 天`;

      await this.plantStore.saveCityRecord({
        cityKey: snapshot.cityKey,
        cityName: snapshot.cityName,
        snapshot,
        plant: nextPlant,
        lastFetchedAt: new Date().toISOString()
      });
      await this.reloadStoredRecords(true);
      this.requestRedraw();
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  private async applyMockDays(profile: string, days: number = PLANT_MATURITY_DAYS): Promise<void> {
    if (this.loading || !this.isTestCity()) {
      return;
    }
    const city = this.currentSnapshot === null ? '测试市' : this.currentSnapshot.cityName;
    const effectiveDays = Math.max(1, Math.round(days));
    this.loading = true;
    this.statusText = `正在写入 ${city} 的 ${effectiveDays} 天模拟数据`;
    try {
      let snapshot = this.mockAqiService.createSnapshot(city, 0, profile);
      let plant: PlantState | null = await this.plantStore.getStoredPlant(snapshot.cityKey);
      for (let i = 0; i < effectiveDays; i++) {
        snapshot = this.mockAqiService.createSnapshot(city, i, profile);
        plant = updatePlantWithSnapshot(plant, snapshot);
      }
      const finalPlant = plant;
      if (finalPlant !== null) {
        await this.plantStore.saveCityRecord({
          cityKey: snapshot.cityKey,
          cityName: snapshot.cityName,
          snapshot,
          plant: finalPlant,
          lastFetchedAt: new Date().toISOString()
        });
      }
      this.lastFetchText = this.formatFetchTime();
      await this.reloadStoredRecords(true);
      this.statusText = `已写入 ${snapshot.cityName} 的 ${effectiveDays} 天模拟数据`;
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  private getCurrentMockProfile(): string {
    if (this.currentSnapshot !== null && this.currentSnapshot.dominantPollutant === 'pm25') {
      return 'pm25';
    }
    if (this.currentPlant.averageStress > 0.56) {
      return 'polluted';
    }
    return 'clean';
  }

  private formatMockValue(value: number | null): string {
    if (value === null) {
      return '';
    }
    return Math.round(value).toString();
  }

  private setMockEditorFromProfile(profile: string): void {
    const city = this.currentSnapshot === null ? '测试市' : this.currentSnapshot.cityName;
    const dayOffset = getPlantGrowthDays(this.currentPlant);
    const snapshot = this.mockAqiService.createSnapshot(city, dayOffset, profile);
    this.testPm25Text = this.formatMockValue(snapshot.pollutants.pm25);
    this.testPm10Text = this.formatMockValue(snapshot.pollutants.pm10);
    this.testO3Text = this.formatMockValue(snapshot.pollutants.o3);
    this.testNo2Text = this.formatMockValue(snapshot.pollutants.no2);
    this.testSo2Text = this.formatMockValue(snapshot.pollutants.so2);
    this.testCoText = this.formatMockValue(snapshot.pollutants.co);
    this.uiRevision += 1;
    if (profile === 'polluted') {
      this.statusText = '已预填污染模板，编辑后点击提交更新';
    } else if (profile === 'pm25') {
      this.statusText = '已预填 PM2.5 模板，编辑后点击提交更新';
    } else {
      this.statusText = '已预填清洁模板，编辑后点击提交更新';
    }
  }

  private parseMockValue(text: string): number | null {
    const value = Number(text.trim());
    if (isNaN(value) || value < 0) {
      return null;
    }
    return value;
  }

  private updateMockEditorValue(key: string, value: string): void {
    if (key === 'pm25') {
      this.testPm25Text = value;
    } else if (key === 'pm10') {
      this.testPm10Text = value;
    } else if (key === 'o3') {
      this.testO3Text = value;
    } else if (key === 'no2') {
      this.testNo2Text = value;
    } else if (key === 'so2') {
      this.testSo2Text = value;
    } else if (key === 'co') {
      this.testCoText = value;
    }
  }

  private getEditedMockPollutants(): PollutantVector {
    return {
      pm25: this.parseMockValue(this.testPm25Text),
      pm10: this.parseMockValue(this.testPm10Text),
      o3: this.parseMockValue(this.testO3Text),
      no2: this.parseMockValue(this.testNo2Text),
      so2: this.parseMockValue(this.testSo2Text),
      co: this.parseMockValue(this.testCoText)
    };
  }

  private async submitEditedMockDay(): Promise<void> {
    if (this.loading || !this.isTestCity()) {
      return;
    }
    const city = this.currentSnapshot === null ? '测试市' : this.currentSnapshot.cityName;
    const dayOffset = getPlantGrowthDays(this.currentPlant);
    this.loading = true;
    this.statusText = `正在提交 ${city} 的自定义模拟数据`;
    try {
      const snapshot = this.mockAqiService.createSnapshotWithPollutants(city, dayOffset, this.getEditedMockPollutants());
      const storedPlant = await this.plantStore.getStoredPlant(snapshot.cityKey);
      const nextPlant = updatePlantWithSnapshot(storedPlant, snapshot);
      await this.plantStore.saveCityRecord({
        cityKey: snapshot.cityKey,
        cityName: snapshot.cityName,
        snapshot,
        plant: nextPlant,
        lastFetchedAt: new Date().toISOString()
      });
      this.lastFetchText = this.formatFetchTime();
      await this.reloadStoredRecords(true);
      this.statusText = `已提交第 ${getPlantGrowthDays(nextPlant)} 日自定义数据`;
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  private async appendMockDay(): Promise<void> {
    if (this.loading || !this.isTestCity()) {
      return;
    }
    const city = this.currentSnapshot === null ? '测试市' : this.currentSnapshot.cityName;
    const dayOffset = getPlantGrowthDays(this.currentPlant);
    const profile = this.getCurrentMockProfile();
    this.loading = true;
    this.statusText = `正在为 ${city} 增加 1 天模拟数据`;
    try {
      const snapshot = this.mockAqiService.createSnapshot(city, dayOffset, profile);
      const storedPlant = await this.plantStore.getStoredPlant(snapshot.cityKey);
      const nextPlant = updatePlantWithSnapshot(storedPlant, snapshot);
      await this.plantStore.saveCityRecord({
        cityKey: snapshot.cityKey,
        cityName: snapshot.cityName,
        snapshot,
        plant: nextPlant,
        lastFetchedAt: new Date().toISOString()
      });
      this.lastFetchText = this.formatFetchTime();
      await this.reloadStoredRecords(true);
      this.statusText = `已增加到第 ${getPlantGrowthDays(nextPlant)} 日`;
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  private async resetMockFirstDay(): Promise<void> {
    if (this.loading || !this.isTestCity()) {
      return;
    }
    const city = this.currentSnapshot === null ? '测试市' : this.currentSnapshot.cityName;
    const profile = this.getCurrentMockProfile();
    this.loading = true;
    this.statusText = `正在把 ${city} 重置为第 1 天`;
    try {
      const snapshot = this.mockAqiService.createSnapshot(city, 0, profile);
      const nextPlant = updatePlantWithSnapshot(null, snapshot);
      await this.plantStore.saveCityRecord({
        cityKey: snapshot.cityKey,
        cityName: snapshot.cityName,
        snapshot,
        plant: nextPlant,
        lastFetchedAt: new Date().toISOString()
      });
      this.lastFetchText = this.formatFetchTime();
      await this.reloadStoredRecords(true);
      this.statusText = `已重置为第 1/${PLANT_MATURITY_DAYS} 日`;
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  private async regenerateUserSeed(): Promise<void> {
    if (this.loading || !this.isTestCity()) {
      return;
    }
    this.loading = true;
    this.statusText = '正在重新生成用户植物 seed';
    try {
      this.installSeed = await this.plantStore.regenerateInstallSeed();
      await this.reloadStoredRecords(true);
      this.statusText = '已重新生成用户 seed，测试市植物将以新的个体基因呈现';
      this.requestRedraw();
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  private getErrorMessage(error: Error | Object): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return '暂时无法获取空气质量数据';
  }

  private requestRedraw(): void {
    setTimeout(() => {
      this.drawPlant();
    }, 40);
  }

  private async handlePlantTap(): Promise<void> {
    if (this.shouldRefreshCurrentCityOnTap()) {
      this.statusText = '正在更新本小时空气数据';
      await this.refreshCurrent();
      return;
    }
    if (this.interactionActive) {
      return;
    }
    const growthDays = getPlantGrowthDays(this.currentPlant);
    this.interactionActive = true;
    this.touchPulse = 1;
    this.leafBurstActive = growthDays >= 7;
    this.leafBurstFrame = 0;
    this.statusText = this.leafBurstActive ? '成熟叶片被轻轻惊起' : '幼苗被风推了一下';
    this.drawPlant();
  }

  private async openCitySwitch(): Promise<void> {
    try {
      await router.pushUrl({ url: 'pages/CitySwitch' });
    } catch (error) {
      this.statusText = '暂时无法打开城市切换页面';
    }
  }

  private toggleDetailLayout(): void {
    this.detailLayoutTarget = this.detailLayoutTarget < 0.5 ? 1 : 0;
  }

  private getCityName(): string {
    return this.displayCityName;
  }

  private getAqiText(): string {
    return this.displayAqiText;
  }

  private getQualityText(): string {
    return this.displayQualityText;
  }

  private getObservedText(): string {
    return this.displayObservedText;
  }

  private getDominantText(): string {
    return this.displayDominantText;
  }

  private getMissingText(): string {
    return this.displayMissingText;
  }

  private getSourceText(): string {
    return this.displaySourceText;
  }

  private getPlantMoodText(): string {
    const growthDays = getPlantGrowthDays(this.currentPlant);
    if (growthDays === 0) {
      return '待发芽';
    }
    if (growthDays < PLANT_MATURITY_DAYS) {
      return '幼苗';
    }
    const stress = this.currentPlant.averageStress;
    if (stress < 0.28) {
      return '舒展';
    }
    if (stress < 0.52) {
      return '平稳';
    }
    if (stress < 0.76) {
      return '承压';
    }
    return '低垂';
  }

  private getQualityColorValue(): string {
    if (this.currentSnapshot === null) {
      return '#587064';
    }
    return getQualityColor(this.currentSnapshot.aqi);
  }

  private getPlantAccentColor(): string {
    const palette = this.plantMorphologyService.buildPaletteForPlant(normalizePlantState(this.currentPlant), this.installSeed);
    return palette.leaf;
  }

  private getCollectedDaysText(): string {
    const days = getPlantGrowthDays(this.currentPlant);
    if (days >= PLANT_MATURITY_DAYS) {
      return `已收集 ${days} 日`;
    }
    return `已收集 ${days}/${PLANT_MATURITY_DAYS} 日`;
  }

  private isTestCity(): boolean {
    const cityName = this.getCityName();
    if (cityName.indexOf('测试') >= 0) {
      return true;
    }
    if (this.currentSnapshot !== null && this.currentSnapshot.cityKey.indexOf('test') >= 0) {
      return true;
    }
    return false;
  }

  private getDetailPanelHeight(): number {
    return DETAIL_PANEL_HEIGHT;
  }

  private getPlantInfoTopPadding(): number {
    if (!this.isTestCity()) {
      return 88;
    }
    return this.testEditorExpanded ? 246 : 154;
  }

  private getPlantInfoOpacity(): number {
    return Math.max(0, 1 - this.detailLayoutProgress * 2.2);
  }

  private getStressColor(stress: number): string {
    if (stress < 0.30) {
      return '#3C9B6B';
    }
    if (stress < 0.55) {
      return '#A4A94D';
    }
    if (stress < 0.76) {
      return '#D18C43';
    }
    return '#AD5966';
  }

  private getStressText(stress: number): string {
    if (stress < 0.30) {
      return '清爽';
    }
    if (stress < 0.55) {
      return '温和';
    }
    if (stress < 0.76) {
      return '偏高';
    }
    return '紧张';
  }

  private makeGrowthText(plant: PlantState): string {
    const growthDays = getPlantGrowthDays(plant);
    if (growthDays >= PLANT_MATURITY_DAYS) {
      return `成熟 ${growthDays} 天`;
    }
    if (growthDays === 0) {
      return '等待第一天数据';
    }
    return `幼苗 ${growthDays}/${PLANT_MATURITY_DAYS} 天`;
  }

  private getGrowthText(): string {
    return this.displayGrowthText;
  }

  private getStageHintText(): string {
    if (this.loading || this.currentSnapshot === null) {
      return this.statusText;
    }
    if (this.shouldRefreshCurrentCityOnTap()) {
      return this.cityRecords.length > 1 ? '点击植物更新本小时数据 · 左右滑动切换城市' : '点击植物更新本小时数据';
    }
    if (this.cityRecords.length > 1) {
      return this.detailLayoutProgress < 0.5 ? '左右滑动切换城市 · 纵向滑动查看 IAQI' : '左右滑动切换城市 · 纵向滑动收起 IAQI';
    }
    return this.detailLayoutProgress < 0.5 ? '纵向滑动查看 IAQI' : '纵向滑动收起 IAQI';
  }

  private drawPlant(): void {
    if (!this.canvasReady) {
      return;
    }
    const ctx = this.canvasContext;
    const plant = normalizePlantState(this.currentPlant);
    const width = Math.max(280, this.canvasWidth);
    const height = Math.max(620, this.canvasHeight);
    const time = this.animationFrame * 0.18;
    const palette = this.plantMorphologyService.buildPaletteForPlant(plant, this.installSeed);

    ctx.clearRect(0, 0, width, height);
    if (!this.hasCityData()) {
      ctx.fillStyle = '#EEF4E8';
      ctx.fillRect(0, 0, width, height);
      return;
    }
    ctx.fillStyle = palette.background;
    ctx.fillRect(0, 0, width, height);
    this.drawAirParticles(ctx, width, height, plant.particleScore, time, palette.particle);

    if (Math.abs(this.plantDragOffsetX) > 0.5) {
      const dragOffset = this.plantDragOffsetX;
      const targetIndex = this.getDragTargetIndex(dragOffset);
      const hasTarget = targetIndex >= 0 && targetIndex < this.cityRecords.length;
      const currentOffset = hasTarget ? dragOffset : dragOffset * 0.28;
      this.drawPlantBody(ctx, plant, width, height, time, currentOffset, this.touchPulse);
      if (hasTarget) {
        const enteringPlant = normalizePlantState(this.cityRecords[targetIndex].plant);
        const enteringOffset = dragOffset < 0 ? width + dragOffset : -width + dragOffset;
        this.drawPlantBody(ctx, enteringPlant, width, height, time, enteringOffset, 0);
      }
      return;
    }

    const previousPlant = this.transitionPreviousPlant;
    if (previousPlant !== null && this.plantSlideProgress < 1) {
      const eased = 1 - Math.pow(1 - this.plantSlideProgress, 3);
      this.drawPlantBody(
        ctx,
        normalizePlantState(previousPlant),
        width,
        height,
        time,
        eased * width * this.plantSlideDirection,
        0
      );
      this.drawPlantBody(
        ctx,
        plant,
        width,
        height,
        time,
        -(1 - eased) * width * this.plantSlideDirection,
        this.touchPulse
      );
      return;
    }

    if (this.plantSlideProgress >= 1) {
      this.transitionPreviousPlant = null;
    }
    this.drawPlantBody(ctx, plant, width, height, time, 0, this.touchPulse);
  }

  private drawPlantBody(
    ctx: CanvasRenderingContext2D,
    plant: PlantState,
    width: number,
    height: number,
    time: number,
    offsetX: number,
    pulse: number
  ): void {
    const morphology = this.plantMorphologyService.buildMorphology(
      plant,
      this.installSeed,
      width,
      height,
      time,
      offsetX,
      this.detailLayoutProgress * PLANT_DETAIL_SHIFT,
      pulse
    );
    this.drawMorphology(ctx, morphology);
  }

  private drawMorphology(ctx: CanvasRenderingContext2D, morphology: PlantMorphology): void {
    this.drawMorphSoil(ctx, morphology);

    for (let i = 0; i < morphology.branches.length; i++) {
      this.drawMorphBranch(ctx, morphology.branches[i], morphology.palette.lesion);
    }

    for (let i = 0; i < morphology.leaves.length; i++) {
      this.drawMorphLeaf(ctx, morphology.leaves[i], morphology.palette.lesion);
    }

    for (let i = 0; i < morphology.buds.length; i++) {
      this.drawMorphBud(ctx, morphology.buds[i]);
    }
    if (this.leafBurstActive) {
      this.drawLeafBurst(ctx, morphology);
    }
    ctx.globalAlpha = 1;
  }

  private drawMorphSoil(ctx: CanvasRenderingContext2D, morphology: PlantMorphology): void {
    const rootX = morphology.rootX;
    const rootY = morphology.rootY;
    const growth = morphology.growth;
    ctx.globalAlpha = 0.16 + (1 - morphology.stress) * 0.18;
    ctx.fillStyle = morphology.palette.leafShadow;
    ctx.beginPath();
    ctx.ellipse(rootX, rootY + 10, 54 + growth * 58, 18 + growth * 12, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;

    ctx.fillStyle = morphology.palette.soil;
    ctx.beginPath();
    ctx.moveTo(rootX - 54 - growth * 22, rootY + 14);
    ctx.lineTo(rootX + 54 + growth * 22, rootY + 14);
    ctx.lineTo(rootX + 42 + growth * 16, rootY + 64);
    ctx.lineTo(rootX - 42 - growth * 16, rootY + 64);
    ctx.closePath();
    ctx.fill();

    ctx.fillStyle = morphology.palette.soilDark;
    ctx.beginPath();
    ctx.ellipse(rootX, rootY + 13, 62 + growth * 24, 15, 0, 0, Math.PI * 2);
    ctx.fill();
  }

  private drawMorphBranch(ctx: CanvasRenderingContext2D, branch: MorphBranch, lesionColor: string): void {
    ctx.globalAlpha = branch.alpha;
    ctx.strokeStyle = branch.color;
    ctx.lineWidth = branch.width;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(branch.startX, branch.startY);
    ctx.quadraticCurveTo(branch.controlX, branch.controlY, branch.endX, branch.endY);
    ctx.stroke();

    if (branch.rupture > 0.22) {
      const scarX = (branch.startX + branch.controlX + branch.endX) / 3;
      const scarY = (branch.startY + branch.controlY + branch.endY) / 3;
      ctx.globalAlpha = Math.min(0.55, branch.rupture);
      ctx.strokeStyle = lesionColor;
      ctx.lineWidth = Math.max(1.2, branch.width * 0.34);
      ctx.beginPath();
      ctx.moveTo(scarX - branch.width * 1.2, scarY - branch.width * 0.6);
      ctx.lineTo(scarX + branch.width * 1.5, scarY + branch.width * 0.7);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }

  private drawMorphLeaf(ctx: CanvasRenderingContext2D, leaf: MorphLeaf, lesionColor: string): void {
    const directionLength = Math.max(1, Math.sqrt(leaf.dirX * leaf.dirX + leaf.dirY * leaf.dirY));
    const ux = leaf.dirX / directionLength;
    const uy = leaf.dirY / directionLength;
    const px = -uy;
    const py = ux;
    const skew = leaf.damage * 0.28;
    const tipX = leaf.rootX + ux * leaf.length + px * leaf.length * skew;
    const tipY = leaf.rootY + uy * leaf.length + py * leaf.length * skew;
    const midX = leaf.rootX + ux * leaf.length * 0.52;
    const midY = leaf.rootY + uy * leaf.length * 0.52;
    const leftWidth = leaf.width * (1 + leaf.damage * 0.46);
    const rightWidth = leaf.width * Math.max(0.38, 1 - leaf.damage * 0.52);

    ctx.globalAlpha = leaf.alpha;
    ctx.fillStyle = leaf.color;
    ctx.beginPath();
    ctx.moveTo(leaf.rootX, leaf.rootY);
    ctx.quadraticCurveTo(midX + px * leftWidth, midY + py * leftWidth, tipX, tipY);
    ctx.quadraticCurveTo(midX - px * rightWidth, midY - py * rightWidth, leaf.rootX, leaf.rootY);
    ctx.fill();

    if (leaf.damage > 0.32) {
      ctx.globalAlpha = Math.min(0.44, leaf.damage);
      ctx.fillStyle = lesionColor;
      ctx.beginPath();
      ctx.ellipse(midX + px * leaf.width * 0.38, midY + py * leaf.width * 0.38,
        Math.max(1, leaf.width * 0.34), Math.max(1, leaf.width * 0.18), 0, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  private drawMorphBud(ctx: CanvasRenderingContext2D, bud: MorphBud): void {
    ctx.globalAlpha = bud.alpha;
    ctx.fillStyle = bud.color;
    ctx.beginPath();
    ctx.arc(bud.x, bud.y, bud.radius, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;
  }

  private drawLeafBurst(ctx: CanvasRenderingContext2D, morphology: PlantMorphology): void {
    const progress = Math.min(1, this.leafBurstFrame / LEAF_BURST_DURATION);
    const alpha = Math.max(0, 1 - progress);
    const leafCount = morphology.leaves.length;
    const count = Math.min(Math.max(8, leafCount), 16 + Math.round(morphology.growth * 14));
    for (let i = 0; i < count; i++) {
      const n1 = this.burstNoise(i, 1);
      const n2 = this.burstNoise(i, 2);
      const n3 = this.burstNoise(i, 3);
      let startX = morphology.rootX + (n1 - 0.5) * 40;
      let startY = morphology.rootY - 70 - n2 * 60;
      let length = 10 + n2 * 10;
      let width = 3 + n3 * 3;
      let color = i % 3 === 0 ? morphology.palette.leafAccent : morphology.palette.leaf;
      if (leafCount > 0) {
        const sourceIndex = Math.min(leafCount - 1, Math.floor(n1 * leafCount));
        const source = morphology.leaves[sourceIndex];
        startX = source.rootX + source.dirX * source.length * (0.28 + n2 * 0.42);
        startY = source.rootY + source.dirY * source.length * (0.28 + n3 * 0.42);
        length = Math.max(8, source.length * (0.42 + n2 * 0.30));
        width = Math.max(2.4, source.width * (0.58 + n3 * 0.28));
        color = source.damage > 0.38 ? morphology.palette.leafAccent : source.color;
      }
      const driftX = (n2 - 0.5) * (110 + morphology.growth * 70) * progress;
      const fallY = (48 + n3 * 150) * progress;
      const flutter = Math.sin(progress * 12 + i * 0.74) * (10 + n1 * 16);
      const x = startX + driftX + flutter;
      const y = startY + fallY;
      const dirX = Math.cos(progress * Math.PI * 2 + i);
      const dirY = Math.sin(progress * Math.PI * 2 + i) * 0.35 + 0.30;
      this.drawFloatingLeaf(ctx, x, y, dirX, dirY, length, width, color, alpha * (0.28 + n1 * 0.46));
    }
  }

  private drawFloatingLeaf(
    ctx: CanvasRenderingContext2D,
    rootX: number,
    rootY: number,
    dirX: number,
    dirY: number,
    length: number,
    width: number,
    color: string,
    alpha: number
  ): void {
    const directionLength = Math.max(1, Math.sqrt(dirX * dirX + dirY * dirY));
    const ux = dirX / directionLength;
    const uy = dirY / directionLength;
    const px = -uy;
    const py = ux;
    const tipX = rootX + ux * length;
    const tipY = rootY + uy * length;
    const midX = rootX + ux * length * 0.50;
    const midY = rootY + uy * length * 0.50;

    ctx.globalAlpha = alpha;
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.moveTo(rootX, rootY);
    ctx.quadraticCurveTo(midX + px * width, midY + py * width, tipX, tipY);
    ctx.quadraticCurveTo(midX - px * width * 0.7, midY - py * width * 0.7, rootX, rootY);
    ctx.fill();
    ctx.globalAlpha = 1;
  }

  private burstNoise(index: number, salt: number): number {
    const raw = Math.sin((index + 1) * 12.9898 + salt * 78.233 + this.currentCityIndex * 37.719 +
      this.installSeed.length * 0.173) * 43758.5453;
    return raw - Math.floor(raw);
  }

  private drawAirParticles(
    ctx: CanvasRenderingContext2D,
    width: number,
    height: number,
    stress: number,
    time: number,
    color: string
  ): void {
    const count = Math.round(8 + stress * 30);
    ctx.fillStyle = color;
    for (let i = 0; i < count; i++) {
      const drift = Math.sin(time * 0.52 + i * 1.7) * 5;
      const x = 20 + (i * 57 + Math.round(time * 8)) % (width - 40) + drift;
      const y = 24 + (i * 83 + Math.round(time * 3)) % (height - 140);
      const radius = 1 + stress * 2.2;
      ctx.globalAlpha = 0.08 + stress * 0.18;
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  @Builder
  TopInfoBar() {
    Row({ space: 10 }) {
      Column({ space: 1 }) {
        Text('空气花园')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getPlantAccentColor())
        Text(this.loading ? '更新中' : this.getPlantMoodText())
          .fontSize(11)
          .fontColor('#647069')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row({ space: 6 }) {
        Text('⌖')
          .fontSize(16)
          .fontColor(this.getPlantAccentColor())
        Text(this.getCityName())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1F2925')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('56%')
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .backgroundColor('#E7EFE4')
      .borderRadius(10)
      .onClick(() => {
        this.openCitySwitch();
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 14, right: 14 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor('#F7FAF3')
    .borderRadius(14)
    .shadow({ radius: 12, color: '#1A000000', offsetX: 0, offsetY: 4 })
  }

  @Builder
  PlantInfoOverlay() {
    Column({ space: 2 }) {
      Text(this.getAqiText())
        .fontSize(58)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getQualityColorValue())
        .lineHeight(62)
      Row({ space: 8 }) {
        Text(this.getQualityText())
          .fontSize(13)
          .fontColor(Color.White)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(this.getQualityColorValue())
          .borderRadius(8)
        Text(this.getCollectedDaysText())
          .fontSize(13)
          .fontColor('#33413A')
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor('#E7EFE4')
          .borderRadius(8)
      }
      Text(this.getObservedText())
        .fontSize(11)
        .fontColor('#647069')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  MockPollutantInput(label: string, value: string, pollutantKey: string) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(10)
        .fontColor('#5E6A63')
      TextInput({ text: value })
        .id(`${pollutantKey}-${this.uiRevision}`)
        .height(28)
        .fontSize(11)
        .backgroundColor('#FFFFFF')
        .borderRadius(6)
        .onChange((nextValue: string) => {
          this.updateMockEditorValue(pollutantKey, nextValue);
        })
    }
    .layoutWeight(1)
  }

  @Builder
  TestEditorPanel() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Button('预填清洁')
          .height(26)
          .fontSize(10)
          .backgroundColor('#DBEFE3')
          .fontColor('#28664C')
          .borderRadius(6)
          .layoutWeight(1)
          .onClick(() => {
            this.setMockEditorFromProfile('clean');
          })
        Button('预填污染')
          .height(26)
          .fontSize(10)
          .backgroundColor('#F4E5E3')
          .fontColor('#9D4150')
          .borderRadius(6)
          .layoutWeight(1)
          .onClick(() => {
            this.setMockEditorFromProfile('polluted');
          })
        Button('预填PM2.5')
          .height(26)
          .fontSize(10)
          .backgroundColor('#EFE7D8')
          .fontColor('#71583A')
          .borderRadius(6)
          .layoutWeight(1)
          .onClick(() => {
            this.setMockEditorFromProfile('pm25');
          })
        Button('提交更新')
          .height(26)
          .fontSize(10)
          .enabled(!this.loading)
          .backgroundColor('#4E5F86')
          .borderRadius(6)
          .layoutWeight(1)
          .onClick(() => {
            this.submitEditedMockDay();
          })
      }
      .width('100%')

      Row({ space: 5 }) {
        this.MockPollutantInput('PM2.5', this.testPm25Text, 'pm25')
        this.MockPollutantInput('PM10', this.testPm10Text, 'pm10')
        this.MockPollutantInput('O3', this.testO3Text, 'o3')
      }
      .width('100%')

      Row({ space: 5 }) {
        this.MockPollutantInput('NO2', this.testNo2Text, 'no2')
        this.MockPollutantInput('SO2', this.testSo2Text, 'so2')
        this.MockPollutantInput('CO', this.testCoText, 'co')
      }
      .width('100%')

    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .backgroundColor('#DCF8EFD9')
    .borderRadius(10)
  }

  @Builder
  MainTestPanel() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text('测试')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#26312B')
        Text(this.getCollectedDaysText())
          .fontSize(11)
          .fontColor('#5E6A63')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
        Button('+1 天')
          .height(28)
          .fontSize(11)
          .enabled(!this.loading)
          .backgroundColor('#667B68')
          .borderRadius(7)
          .onClick(() => {
            this.appendMockDay();
          })
        Button('首日')
          .height(28)
          .fontSize(11)
          .enabled(!this.loading)
          .backgroundColor('#8A765C')
          .borderRadius(7)
          .onClick(() => {
            this.resetMockFirstDay();
          })
        Button(this.testEditorExpanded ? '收起' : '编辑')
          .height(28)
          .fontSize(11)
          .enabled(!this.loading)
          .backgroundColor('#4E5F86')
          .borderRadius(7)
          .onClick(() => {
            this.testEditorExpanded = !this.testEditorExpanded;
            if (this.testEditorExpanded) {
              this.setMockEditorFromProfile(this.getCurrentMockProfile());
            }
          })
      }
      .width('100%')

      Row({ space: 6 }) {
        Button('清洁 14')
          .height(28)
          .fontSize(11)
          .enabled(!this.loading)
          .backgroundColor('#2F9E6D')
          .borderRadius(7)
          .layoutWeight(1)
          .onClick(() => {
            this.applyMockDays('clean', PLANT_MATURITY_DAYS);
          })
        Button('污染 14')
          .height(28)
          .fontSize(11)
          .enabled(!this.loading)
          .backgroundColor('#B94F5F')
          .borderRadius(7)
          .layoutWeight(1)
          .onClick(() => {
            this.applyMockDays('polluted', PLANT_MATURITY_DAYS);
          })
        Button('PM2.5')
          .height(28)
          .fontSize(11)
          .enabled(!this.loading)
          .backgroundColor('#7D6A50')
          .borderRadius(7)
          .layoutWeight(1)
          .onClick(() => {
            this.applyMockDays('pm25', PLANT_MATURITY_DAYS);
          })
        Button('seed')
          .height(28)
          .fontSize(11)
          .enabled(!this.loading)
          .backgroundColor('#4E5F86')
          .borderRadius(7)
          .layoutWeight(1)
          .onClick(() => {
            this.regenerateUserSeed();
          })
      }
      .width('100%')

      if (this.testEditorExpanded) {
        this.TestEditorPanel()
      }
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor('#DFFFF8EA')
    .borderRadius(12)
    .shadow({ radius: 8, color: '#14000000', offsetX: 0, offsetY: 3 })
  }

  @Builder
  EmptyState() {
    Column({ space: 16 }) {
      Blank()
      Text('选择一座城市')
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor('#26312B')
      Text('还没有可展示的空气植物。先定位或搜索城市，系统会为每座城市保存一株独立植物。')
        .fontSize(14)
        .fontColor('#65716A')
        .lineHeight(21)
        .textAlign(TextAlign.Center)
        .width('78%')
      Button('去选择城市')
        .height(44)
        .fontSize(16)
        .backgroundColor('#2E6D5E')
        .borderRadius(12)
        .padding({ left: 22, right: 22 })
        .onClick(() => {
          this.openCitySwitch();
        })
      Text(this.statusText)
        .fontSize(12)
        .fontColor('#78837C')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Blank()
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 24, right: 24, top: 96, bottom: 36 })
    .backgroundColor('#EEF4E8')
  }

  @Builder
  PlantStage() {
    Stack({ alignContent: Alignment.Center }) {
      Canvas(this.canvasContext)
        .width('100%')
        .height('100%')
        .backgroundColor('#EEF4E8')
        .onAreaChange((oldValue, newValue) => {
          const nextWidth = Number(newValue.width);
          if (!isNaN(nextWidth) && nextWidth > 0 && Math.abs(nextWidth - this.canvasWidth) > 1) {
            this.canvasWidth = nextWidth;
            this.requestRedraw();
          }
          const nextHeight = Number(newValue.height);
          if (!isNaN(nextHeight) && nextHeight > 0 && Math.abs(nextHeight - this.canvasHeight) > 1) {
            this.canvasHeight = nextHeight;
            this.requestRedraw();
          }
        })
        .onReady(() => {
          this.canvasReady = true;
          this.drawPlant();
        })
        .onClick(() => {
          this.handlePlantTap();
        })

      Column() {
        Blank()
        Text(this.getStageHintText())
          .fontSize(12)
          .fontColor('#65716A')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor('#88E1EBDD')
          .borderRadius(8)
          .margin({ bottom: 22 })
      }
      .height('100%')
      .width('100%')
      .alignItems(HorizontalAlign.Center)

      if (this.cityRecords.length > 0) {
        Column() {
          Blank()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#00FFFFFF')
        .gesture(
          PanGesture({ direction: PanDirection.Horizontal, distance: 3 })
            .onActionUpdate((event) => {
              this.handlePlantDragUpdate(Number(event.offsetX));
            })
            .onActionEnd(() => {
              this.handlePlantDragEnd();
            })
        )
        .onClick(() => {
          this.handlePlantTap();
        })
      }
    }
    .width('100%')
    .height('100%')
    .gesture(
      PanGesture({ direction: PanDirection.Vertical, distance: 10 })
        .onActionEnd(() => {
          this.toggleDetailLayout();
        })
    )
  }

  @Builder
  DataSheet() {
    Column({ space: 14 }) {
      this.PollutantPanel()
      this.SourcePanel()
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 22, bottom: 34 })
    .backgroundColor('#E8F0E2')
    .borderRadius(24)
    .height(this.getDetailPanelHeight())
  }

  @Builder
  Header() {
    Row() {
      Column({ space: 4 }) {
        Text('空气花园')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor('#202925')
        Text('电子植物 · 城市空气质量')
          .fontSize(13)
          .fontColor('#6A736D')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(this.loading ? '更新中' : this.getPlantMoodText())
        .fontSize(13)
        .fontColor(Color.White)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(this.getQualityColorValue())
        .borderRadius(8)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  SearchPanel() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        TextInput({ placeholder: '输入城市，如 北京 / 上海 / Chengdu', text: this.cityInput })
          .height(42)
          .fontSize(15)
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.cityInput = value;
          })

        Button('搜索')
          .height(42)
          .fontSize(15)
          .enabled(!this.loading)
          .backgroundColor('#2E6D5E')
          .borderRadius(8)
          .onClick(() => {
            this.searchCity();
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Button('定位')
          .height(38)
          .fontSize(14)
          .enabled(!this.loading)
          .backgroundColor('#4E7D82')
          .borderRadius(8)
          .layoutWeight(1)
          .onClick(() => {
            this.refreshByLocation();
          })
        Button('刷新')
          .height(38)
          .fontSize(14)
          .enabled(!this.loading)
          .backgroundColor('#7D6A50')
          .borderRadius(8)
          .layoutWeight(1)
          .onClick(() => {
            this.refreshCurrent();
          })
      }
      .width('100%')

      Text(this.statusText)
        .fontSize(13)
        .fontColor('#59635D')
        .lineHeight(20)
        .width('100%')
    }
    .width('100%')
  }

  @Builder
  PlantPanel() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text(this.getCityName())
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#212B27')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.getObservedText())
            .fontSize(12)
            .fontColor('#68736D')
            .maxLines(2)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column({ space: 2 }) {
          Text(this.getAqiText())
            .fontSize(40)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getQualityColorValue())
          Text(this.getQualityText())
            .fontSize(13)
            .fontColor('#5C665F')
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Canvas(this.canvasContext)
        .width('100%')
        .height(CANVAS_HEIGHT)
        .constraintSize({ maxWidth: 420 })
        .borderRadius(8)
        .backgroundColor('#EDF3E7')
        .onAreaChange((oldValue, newValue) => {
          const nextWidth = Number(newValue.width);
          if (!isNaN(nextWidth) && nextWidth > 0 && Math.abs(nextWidth - this.canvasWidth) > 1) {
            this.canvasWidth = nextWidth;
            this.requestRedraw();
          }
        })
        .onReady(() => {
          this.canvasReady = true;
          this.drawPlant();
        })
        .onClick(() => {
          this.handlePlantTap();
        })

      Row() {
        Text(this.getDominantText())
          .fontSize(13)
          .fontColor('#4A564F')
          .layoutWeight(1)
        Text(this.getGrowthText())
          .fontSize(13)
          .fontColor('#4A564F')
      }
      .width('100%')

      Text(this.lastFetchText)
        .fontSize(12)
        .fontColor('#7C857E')
        .width('100%')
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  PollutantPanel() {
    Column({ space: 10 }) {
      Row() {
        Text('六项污染物')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#242D29')
        Blank()
        Text('IAQI')
          .fontSize(12)
          .fontColor('#69746D')
      }
      .width('100%')

      Grid() {
        ForEach(this.pollutantItems, (item: PollutantDisplayItem) => {
          GridItem() {
            Column({ space: 7 }) {
              Row() {
                Text(item.name)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#27302C')
                Blank()
                Text(item.valueText)
                  .fontSize(13)
                  .fontColor(item.missing ? '#8B928C' : '#27302C')
              }
              .width('100%')

              Progress({ value: Math.round(item.stress * 100), total: 100, type: ProgressType.Linear })
                .height(4)
                .color(this.getStressColor(item.stress))
                .backgroundColor('#E3E7DF')

              Text(this.getStressText(item.stress))
                .fontSize(11)
                .fontColor('#6D766F')
                .width('100%')
            }
            .width('100%')
            .height(82)
            .padding(10)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
          }
        }, (item: PollutantDisplayItem) => `${this.uiRevision}-${item.key}-${item.valueText}`)
      }
      .columnsTemplate('1fr 1fr 1fr')
      .rowsGap(8)
      .columnsGap(8)
      .width('100%')

      if (this.getMissingText().length > 0) {
        Text(this.getMissingText())
          .fontSize(12)
          .fontColor('#8A644B')
          .lineHeight(18)
          .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  SourcePanel() {
    Column({ space: 6 }) {
      Text(this.getSourceText())
        .fontSize(12)
        .fontColor('#66706A')
        .lineHeight(18)
        .width('100%')
      Text('中国环境监测总站接入暂缓，后续可替换为后端数据服务。')
        .fontSize(12)
        .fontColor('#66706A')
        .lineHeight(18)
        .width('100%')
    }
    .width('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.hasCityData()) {
        this.PlantStage()

        Column() {
          this.PlantInfoOverlay()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.getPlantInfoTopPadding() })
        .opacity(this.getPlantInfoOpacity())

        Column() {
          this.DataSheet()
        }
        .width('100%')
        .position({ x: 0, y: '100%' })
        .translate({ y: -this.detailLayoutProgress * this.getDetailPanelHeight() })
        .opacity(this.detailLayoutProgress)
        .gesture(
          PanGesture({ direction: PanDirection.Vertical, distance: 10 })
            .onActionEnd(() => {
              this.toggleDetailLayout();
            })
        )

        if (this.isTestCity()) {
          Column() {
            this.MainTestPanel()
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 80 })
          .zIndex(2)
        }
      } else {
        this.EmptyState()
      }

      Column() {
        this.TopInfoBar()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 18 })
      .zIndex(3)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#EEF4E8')
  }
}
