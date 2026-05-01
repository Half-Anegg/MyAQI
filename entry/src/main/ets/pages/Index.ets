import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { AqiSnapshot, PlantState, PollutantDisplayItem, StoredCityRecord, createInitialPlantState } from '../models/AqiModels';
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

      if (!this.aqiClient.hasToken()) {
        this.statusText = '请先在 ApiConfig.ets 中配置 WAQI token';
        this.requestRedraw();
        return;
      }
      await this.refreshByLocation();
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
      await this.reloadStoredRecords(true);
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
    const shouldSwitch = targetIndex >= 0 && targetIndex < this.cityRecords.length && Math.abs(dragOffset) > width * 0.22;

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
    await this.loadSnapshot(async (): Promise<AqiSnapshot> => {
      return this.aqiClient.fetchByCity(city);
    }, `正在查询 ${city} 的空气质量`);
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
        `植物已吸收这次空气数据，成长 ${Math.min(getPlantGrowthDays(nextPlant), PLANT_MATURITY_DAYS)}/${PLANT_MATURITY_DAYS} 天`;

      await this.plantStore.saveCityRecord({
        cityKey: snapshot.cityKey,
        cityName: snapshot.cityName,
        snapshot,
        plant: nextPlant
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
          plant: finalPlant
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
        plant: nextPlant
      });
      this.lastFetchText = this.formatFetchTime();
      await this.reloadStoredRecords(true);
      this.statusText = `已增加到第 ${Math.min(getPlantGrowthDays(nextPlant), PLANT_MATURITY_DAYS)}/${PLANT_MATURITY_DAYS} 日`;
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
        plant: nextPlant
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

  private handlePlantTap(): void {
    if (this.interactionActive) {
      return;
    }
    const growthDays = getPlantGrowthDays(this.currentPlant);
    this.interactionActive = true;
    this.touchPulse = 1;
    this.leafBurstActive = growthDays >= PLANT_MATURITY_DAYS;
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
    const days = Math.min(getPlantGrowthDays(this.currentPlant), PLANT_MATURITY_DAYS);
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
    return this.isTestCity() ? 154 : 88;
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
      return `成熟 ${PLANT_MATURITY_DAYS}/${PLANT_MATURITY_DAYS} 天`;
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
    const count = 14 + Math.round(morphology.growth * 10);
    for (let i = 0; i < count; i++) {
      const n1 = this.burstNoise(i, 1);
      const n2 = this.burstNoise(i, 2);
      const n3 = this.burstNoise(i, 3);
      const startX = morphology.rootX + (n1 - 0.5) * (90 + morphology.growth * 120);
      const startY = morphology.rootY - 170 - n2 * (120 + morphology.growth * 140);
      const driftX = (n2 - 0.5) * (140 + morphology.growth * 90) * progress;
      const fallY = (80 + n3 * 180) * progress;
      const flutter = Math.sin(progress * 10 + i * 0.74) * (14 + n1 * 18);
      const x = startX + driftX + flutter;
      const y = startY + fallY;
      const dirX = Math.cos(progress * Math.PI * 2 + i);
      const dirY = Math.sin(progress * Math.PI * 2 + i) * 0.35 + 0.30;
      this.drawFloatingLeaf(ctx, x, y, dirX, dirY, 11 + n2 * 11, 3 + n3 * 3,
        i % 3 === 0 ? morphology.palette.leafAccent : morphology.palette.leaf, alpha * (0.28 + n1 * 0.46));
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
        .fontSize(70)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getQualityColorValue())
        .lineHeight(74)
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
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor('#FFF8EA')
    .borderRadius(12)
    .shadow({ radius: 8, color: '#14000000', offsetX: 0, offsetY: 3 })
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
          .backgroundColor('#E1EBDD')
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
          PanGesture({ direction: PanDirection.Horizontal, distance: 8 })
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
      this.PlantStage()

      Column() {
        this.PlantInfoOverlay()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.getPlantInfoTopPadding() })

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

      Column() {
        this.TopInfoBar()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 18 })

      if (this.isTestCity()) {
        Column() {
          this.MainTestPanel()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 80 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#EEF4E8')
  }
}
