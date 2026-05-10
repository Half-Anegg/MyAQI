import { common } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { FunctionComponent, FunctionController } from '@kit.AgentFrameworkKit';
import { router } from '@kit.ArkUI';
import { ShareAppType, SharePicker, ShareWay } from 'aggregated_share';
import {
  AqiSnapshot,
  DEFAULT_PLANT_SPECIES,
  DEFAULT_POT_STYLE,
  PlantSpeciesId,
  PlantState,
  POLLUTANT_KEYS,
  PollutantDisplayItem,
  PollutantVector,
  PotStyleId,
  StoredCityRecord,
  createInitialPlantState,
  getPollutantValue
} from '../models/AqiModels';
import { AqiClient } from '../services/AqiClient';
import { MockAqiService } from '../services/MockAqiService';
import { MorphBranch, MorphBud, MorphLeaf, PlantMorphology, PlantMorphologyService } from '../services/PlantMorphologyService';
import {
  buildPollutantItems,
  getPlantGrowthStageText,
  getPlantGrowthDays,
  PLANT_MATURITY_DAYS,
  getQualityColor,
  normalizePlantState,
  updatePlantWithSnapshot
} from '../services/PlantAlgorithm';
import { PlantStore } from '../storage/PlantStore';

const APP_DISPLAY_NAME: string = '一叶知气·空气花园';
const PREVIEW_CITY_KEY: string = 'preview';
const PREVIEW_CITY_NAME: string = APP_DISPLAY_NAME;
const DEFAULT_CANVAS_WIDTH: number = 320;
const CANVAS_HEIGHT: number = 760;
const PLANT_ANIMATION_INTERVAL: number = 16;
const DETAIL_PANEL_HEIGHT: number = 344;
const LEAF_BURST_DURATION: number = 72;
const ABSORB_ANIMATION_DURATION: number = 74;
const AQI_REQUEST_TIMEOUT_MS: number = 20000;
const SHARE_POSTER_COMPONENT_ID: string = 'aqiSharePosterSnapshot';
const SHARE_POSTER_WIDTH: number = 360;
const SHARE_POSTER_HEIGHT: number = 640;
const SHARE_POSTER_PLANT_HEIGHT: number = 286;
const SHARE_POSTER_RADAR_WIDTH: number = 152;
const SHARE_POSTER_RADAR_HEIGHT: number = 132;
const TOP_BAR_ICON_SIZE: number = 27;
const AQI_AGENT_ID: string = 'agentbd430f4f8928446684ab1eb7a5944bc8';

@Entry
@Component
struct Index {
  private aqiClient: AqiClient = new AqiClient();
  private mockAqiService: MockAqiService = new MockAqiService();
  private plantMorphologyService: PlantMorphologyService = new PlantMorphologyService();
  private plantStore: PlantStore = new PlantStore();
  private aqiAgentController: FunctionController = new FunctionController();
  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);
  private appearancePreviewSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private appearancePreviewContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.appearancePreviewSettings);
  private posterPlantSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private posterPlantContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.posterPlantSettings);
  private posterRadarSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private posterRadarContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.posterRadarSettings);
  private canvasReady: boolean = false;
  private appearancePreviewReady: boolean = false;
  private posterPlantReady: boolean = false;
  private posterRadarReady: boolean = false;
  private animationTimer: number = -1;
  private animationFrame: number = 0;
  private touchPulse: number = 0;
  private plantSlideProgress: number = 1;
  private plantSlideDirection: number = 1;
  private plantDragOffsetX: number = 0;
  private plantDragTargetIndex: number = -1;
  private plantDragReturning: boolean = false;
  private particleWindDirection: number = 1;
  private transitionPreviousPlant: PlantState | null = null;
  private transitionPreviousPotStyle: PotStyleId = DEFAULT_POT_STYLE;
  private storeReady: boolean = false;
  private preparing: boolean = false;
  private detailLayoutTarget: number = 0;
  private installSeed: string = 'preview_seed';
  private interactionActive: boolean = false;
  private leafBurstActive: boolean = false;
  private leafBurstFrame: number = 0;
  private absorbActive: boolean = false;
  private absorbFrame: number = 0;
  private absorbLevel: number = 0;
  private absorbSeed: number = 0;
  private loadRequestSequence: number = 0;
  private refreshEligibilityHourKey: string = '';

  @State loading: boolean = false;
  @State shareLoading: boolean = false;
  @State canRefreshCurrentCity: boolean = false;
  @State refreshHintRevision: number = 0;
  @State sharePosterRevision: number = 0;
  @State statusText: string = '正在准备一叶知气';
  @State @Watch('onDataModelChanged') currentSnapshot: AqiSnapshot | null = null;
  @State @Watch('onDataModelChanged') currentPlant: PlantState = createInitialPlantState(PREVIEW_CITY_KEY, PREVIEW_CITY_NAME);
  @State canvasWidth: number = DEFAULT_CANVAS_WIDTH;
  @State canvasHeight: number = CANVAS_HEIGHT;
  @State viewportWidth: number = 0;
  @State viewportHeight: number = 0;
  @State uiRevision: number = 0;
  @State displayCityName: string = '未选择城市';
  @State displayAqiText: string = '--';
  @State displayQualityText: string = '等待数据';
  @State displayObservedText: string = '暂无更新时间';
  @State displayDominantText: string = '主要污染物 暂无';
  @State displayMissingText: string = '';
  @State displaySourceText: string = '数据来源：WAQI，当前仅用于免费非商业演示。';
  @State lastFetchText: string = '尚未刷新';
  @State cityRecords: StoredCityRecord[] = [];
  @State currentCityIndex: number = 0;
  @State detailLayoutProgress: number = 0;
  @State testEditorExpanded: boolean = false;
  @State mockEditorRevision: number = 0;
  @State testPm25Text: string = '35';
  @State testPm10Text: string = '45';
  @State testO3Text: string = '50';
  @State testNo2Text: string = '28';
  @State testSo2Text: string = '8';
  @State testCoText: string = '4';
  @State showAppearancePicker: boolean = false;
  @State selectedPlantSpecies: PlantSpeciesId = DEFAULT_PLANT_SPECIES;
  @State selectedPotStyle: PotStyleId = DEFAULT_POT_STYLE;
  @State appearancePreviewWidth: number = 320;
  @State appearancePreviewHeight: number = 236;
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
      const currentHourKey = this.getHourKeyFromDate(new Date());
      if (currentHourKey !== this.refreshEligibilityHourKey) {
        this.refreshEligibilityHourKey = currentHourKey;
        this.rebuildRefreshEligibility();
      }
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
      if (this.absorbActive) {
        this.absorbFrame += 1;
        if (this.absorbFrame >= ABSORB_ANIMATION_DURATION) {
          this.absorbActive = false;
          this.absorbFrame = 0;
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
      if (this.showAppearancePicker && this.appearancePreviewReady) {
        this.drawAppearancePreview();
      }
    }, PLANT_ANIMATION_INTERVAL);
  }

  private stopPlantAnimation(): void {
    if (this.animationTimer < 0) {
      return;
    }
    clearInterval(this.animationTimer);
    this.animationTimer = -1;
  }

  onDataModelChanged(_changedProperty: string): void {
    this.rebuildDisplayState();
    this.requestRedraw();
    this.requestSharePosterRedraw();
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
      '主要污染物 暂无' : `主要污染物 ${this.getPollutantLabel(snapshot.dominantPollutant)}`;
    this.displayMissingText = snapshot === null || snapshot.missingPollutants.length === 0 ?
      '' : `缺失 ${snapshot.missingPollutants.join('、')}，对应植物参数沿用上一状态`;
    this.displaySourceText = snapshot === null ?
      '数据来源：WAQI，当前仅用于免费非商业演示。' :
      `数据来源：${snapshot.sourceName}，当前仅用于免费非商业演示。`;
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
    return this.getHourKeyFromDate(date);
  }

  private getHourKeyFromDate(date: Date): string {
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

  private getRecordByCityKey(cityKey: string): StoredCityRecord | null {
    for (let i = 0; i < this.cityRecords.length; i++) {
      if (this.cityRecords[i].cityKey === cityKey) {
        return this.cityRecords[i];
      }
    }
    return null;
  }

  private makeRecordForSave(
    snapshot: AqiSnapshot,
    plant: PlantState,
    lastFetchedAt: string,
    newCityAppearanceConfigured: boolean
  ): StoredCityRecord {
    const storedRecord = this.getRecordByCityKey(snapshot.cityKey);
    return {
      cityKey: snapshot.cityKey,
      cityName: snapshot.cityName,
      snapshot,
      plant,
      lastFetchedAt,
      plantSpecies: storedRecord === null ? DEFAULT_PLANT_SPECIES : storedRecord.plantSpecies,
      potStyle: storedRecord === null ? DEFAULT_POT_STYLE : storedRecord.potStyle,
      appearanceConfigured: storedRecord === null ? newCityAppearanceConfigured : storedRecord.appearanceConfigured
    };
  }

  private getCurrentPotStyle(): PotStyleId {
    const record = this.getCurrentRecord();
    return record === null ? DEFAULT_POT_STYLE : record.potStyle;
  }

  private computeCanRefreshCurrentCity(): boolean {
    if (this.loading || this.currentSnapshot === null || this.isTestCity()) {
      return false;
    }
    if (!this.aqiClient.hasToken()) {
      return false;
    }
    const record = this.getCurrentRecord();
    if (record === null || record.lastFetchedAt.length === 0) {
      return true;
    }
    const lastHourKey = this.getHourKey(record.lastFetchedAt);
    if (lastHourKey.length === 0) {
      return true;
    }
    return lastHourKey !== this.getHourKeyFromDate(new Date());
  }

  private rebuildRefreshEligibility(): void {
    const currentHourKey = this.getHourKeyFromDate(new Date());
    this.refreshEligibilityHourKey = currentHourKey;
    const nextCanRefresh = this.computeCanRefreshCurrentCity();
    if (this.canRefreshCurrentCity !== nextCanRefresh) {
      this.canRefreshCurrentCity = nextCanRefresh;
    }
    this.refreshHintRevision += 1;
  }

  private shouldRefreshCurrentCityOnTap(): boolean {
    return this.canRefreshCurrentCity;
  }

  private hasCityData(): boolean {
    return this.currentSnapshot !== null && this.cityRecords.length > 0;
  }

  private clearCurrentCityState(): void {
    this.currentSnapshot = null;
    this.currentPlant = createInitialPlantState(PREVIEW_CITY_KEY, PREVIEW_CITY_NAME);
    this.currentCityIndex = 0;
    this.showAppearancePicker = false;
    this.selectedPlantSpecies = DEFAULT_PLANT_SPECIES;
    this.selectedPotStyle = DEFAULT_POT_STYLE;
    this.statusText = '请选择城市，开始培育空气植物';
    this.rebuildDisplayState();
    this.rebuildRefreshEligibility();
    this.requestRedraw();
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
      this.rebuildRefreshEligibility();
    }
  }

  private async reloadStoredRecords(selectLastCity: boolean): Promise<boolean> {
    const records = await this.plantStore.getAllCityRecords();
    this.cityRecords = records;
    if (records.length === 0) {
      this.currentCityIndex = 0;
      this.showAppearancePicker = false;
      this.rebuildRefreshEligibility();
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
    } finally {
      this.rebuildRefreshEligibility();
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
      this.transitionPreviousPotStyle = this.getCurrentPotStyle();
      this.plantSlideDirection = index > this.currentCityIndex ? -1 : 1;
      this.particleWindDirection = this.plantSlideDirection;
      this.plantSlideProgress = Math.max(0, Math.min(1, transitionProgress));
    }
    this.currentCityIndex = index;
    this.currentSnapshot = record.snapshot === null ? null : this.cloneSnapshot(record.snapshot);
    this.currentPlant = normalizePlantState(record.plant);
    this.selectedPlantSpecies = record.plantSpecies;
    this.selectedPotStyle = record.potStyle;
    this.showAppearancePicker = !record.appearanceConfigured;
    this.rebuildDisplayState();
    this.rebuildRefreshEligibility();
    this.requestRedraw();
    if (this.showAppearancePicker) {
      this.requestAppearancePreviewRedraw();
    }
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
    if (Math.abs(this.plantDragOffsetX) > 0.5) {
      this.particleWindDirection = this.plantDragOffsetX < 0 ? -1 : 1;
    }
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
    this.particleWindDirection = this.plantSlideDirection;

    try {
      await this.plantStore.saveLastCityKey(this.cityRecords[targetIndex].cityKey);
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    }
  }

  private async refreshCurrentFromNetwork(): Promise<void> {
    if (this.loading || this.currentSnapshot === null) {
      return;
    }
    const record = this.getCurrentRecord();
    const city = record === null ? this.currentSnapshot.cityName : record.cityName;
    await this.loadSnapshot(async (): Promise<AqiSnapshot> => {
      return this.aqiClient.fetchByCity(city);
    }, `正在更新 ${city} 的空气质量`);
  }

  private async runSnapshotLoaderWithTimeout(loader: () => Promise<AqiSnapshot>): Promise<AqiSnapshot> {
    let timeoutId: number = -1;
    return await new Promise<AqiSnapshot>((resolve, reject) => {
      timeoutId = setTimeout(() => {
        reject(new Error('AQI 请求超时，请检查网络后重试'));
      }, AQI_REQUEST_TIMEOUT_MS);
      loader().then((snapshot: AqiSnapshot) => {
        clearTimeout(timeoutId);
        resolve(snapshot);
      }).catch((error: Error | Object) => {
        clearTimeout(timeoutId);
        reject(error);
      });
    });
  }

  private async loadSnapshot(loader: () => Promise<AqiSnapshot>, loadingText: string): Promise<void> {
    if (!this.aqiClient.hasToken()) {
      this.statusText = '请先在 ApiConfig.ets 中配置 WAQI token';
      this.rebuildRefreshEligibility();
      return;
    }

    const requestId = this.loadRequestSequence + 1;
    this.loadRequestSequence = requestId;
    this.loading = true;
    this.statusText = loadingText;
    this.rebuildRefreshEligibility();
    try {
      const snapshot = await this.runSnapshotLoaderWithTimeout(loader);
      if (requestId !== this.loadRequestSequence) {
        return;
      }
      const storedPlant = await this.plantStore.getStoredPlant(snapshot.cityKey);
      const repeatedObservation = storedPlant !== null &&
        storedPlant.lastObservedAt === snapshot.observedAt &&
        snapshot.observedAt.length > 0;
      const nextPlant = updatePlantWithSnapshot(storedPlant, snapshot);

      this.currentSnapshot = this.cloneSnapshot(snapshot);
      this.currentPlant = normalizePlantState(nextPlant);
      this.lastFetchText = this.formatFetchTime();
      this.rebuildDisplayState();
      this.statusText = repeatedObservation ? '已是该城市的最新数据，植物状态未重复累计' :
        `植物已吸收这次空气数据，成长 ${getPlantGrowthDays(nextPlant)} 天`;
      if (!repeatedObservation) {
        this.startAbsorbAnimation(snapshot);
      }

      const fetchedAt = new Date().toISOString();
      await this.plantStore.saveCityRecord(
        this.makeRecordForSave(snapshot, nextPlant, fetchedAt, false)
      );
      await this.reloadStoredRecords(true);
      this.requestRedraw();
    } catch (error) {
      if (requestId === this.loadRequestSequence) {
        this.statusText = this.getRefreshErrorMessage(error);
      }
    } finally {
      if (requestId === this.loadRequestSequence) {
        this.loading = false;
        this.rebuildRefreshEligibility();
      }
    }
  }

  private async applyMockDays(profile: string, days: number = PLANT_MATURITY_DAYS): Promise<void> {
    if (this.loading || !this.isTestCity()) {
      return;
    }
    const city = this.currentSnapshot === null ? '测试市' : this.currentSnapshot.cityName;
    const effectiveDays = Math.max(1, Math.round(days));
    this.setMockEditorFromProfile(profile);
    const pollutants = this.getEditedMockPollutants();
    this.loading = true;
    this.statusText = `正在写入 ${city} 的 ${effectiveDays} 天模拟数据`;
    try {
      let snapshot = this.mockAqiService.createSnapshotWithPollutants(city, 0, pollutants);
      let plant: PlantState | null = await this.plantStore.getStoredPlant(snapshot.cityKey);
      for (let i = 0; i < effectiveDays; i++) {
        snapshot = this.mockAqiService.createSnapshotWithPollutants(city, i, pollutants);
        plant = updatePlantWithSnapshot(plant, snapshot);
      }
      const finalPlant = plant;
      if (finalPlant !== null) {
        await this.plantStore.saveCityRecord(
          this.makeRecordForSave(snapshot, finalPlant, new Date().toISOString(), true)
        );
      }
      this.lastFetchText = this.formatFetchTime();
      this.startAbsorbAnimation(snapshot);
      await this.reloadStoredRecords(true);
      this.statusText = `已写入 ${snapshot.cityName} 的 ${effectiveDays} 天模拟数据`;
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    } finally {
      this.loading = false;
      this.rebuildRefreshEligibility();
    }
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
    this.mockEditorRevision += 1;
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

  private getMockSliderValue(text: string): number {
    const value = Number(text.trim());
    if (isNaN(value) || value < 0) {
      return 0;
    }
    if (value > 300) {
      return 300;
    }
    return Math.round(value);
  }

  private getMockSliderText(value: number): string {
    if (isNaN(value) || value < 0) {
      return '0';
    }
    return Math.round(value).toString();
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

  private getMockEditorValue(key: string): string {
    if (key === 'pm25') {
      return this.testPm25Text;
    }
    if (key === 'pm10') {
      return this.testPm10Text;
    }
    if (key === 'o3') {
      return this.testO3Text;
    }
    if (key === 'no2') {
      return this.testNo2Text;
    }
    if (key === 'so2') {
      return this.testSo2Text;
    }
    if (key === 'co') {
      return this.testCoText;
    }
    return '0';
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

  private createEditedMockSnapshot(city: string, dayOffset: number): AqiSnapshot {
    return this.mockAqiService.createSnapshotWithPollutants(city, dayOffset, this.getEditedMockPollutants());
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
      const snapshot = this.createEditedMockSnapshot(city, dayOffset);
      const storedPlant = await this.plantStore.getStoredPlant(snapshot.cityKey);
      const nextPlant = updatePlantWithSnapshot(storedPlant, snapshot);
      await this.plantStore.saveCityRecord(
        this.makeRecordForSave(snapshot, nextPlant, new Date().toISOString(), true)
      );
      this.lastFetchText = this.formatFetchTime();
      this.startAbsorbAnimation(snapshot);
      await this.reloadStoredRecords(true);
      this.statusText = `已提交第 ${getPlantGrowthDays(nextPlant)} 日自定义数据`;
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    } finally {
      this.loading = false;
      this.rebuildRefreshEligibility();
    }
  }

  private async appendMockDay(): Promise<void> {
    if (this.loading || !this.isTestCity()) {
      return;
    }
    const city = this.currentSnapshot === null ? '测试市' : this.currentSnapshot.cityName;
    const dayOffset = getPlantGrowthDays(this.currentPlant);
    this.loading = true;
    this.statusText = `正在为 ${city} 增加 1 天模拟数据`;
    try {
      const snapshot = this.createEditedMockSnapshot(city, dayOffset);
      const storedPlant = await this.plantStore.getStoredPlant(snapshot.cityKey);
      const nextPlant = updatePlantWithSnapshot(storedPlant, snapshot);
      await this.plantStore.saveCityRecord(
        this.makeRecordForSave(snapshot, nextPlant, new Date().toISOString(), true)
      );
      this.lastFetchText = this.formatFetchTime();
      this.startAbsorbAnimation(snapshot);
      await this.reloadStoredRecords(true);
      this.statusText = `已增加到第 ${getPlantGrowthDays(nextPlant)} 日`;
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    } finally {
      this.loading = false;
      this.rebuildRefreshEligibility();
    }
  }

  private async resetMockFirstDay(): Promise<void> {
    if (this.loading || !this.isTestCity()) {
      return;
    }
    const city = this.currentSnapshot === null ? '测试市' : this.currentSnapshot.cityName;
    this.loading = true;
    this.statusText = `正在把 ${city} 重置为第 1 天`;
    try {
      const snapshot = this.createEditedMockSnapshot(city, 0);
      const nextPlant = updatePlantWithSnapshot(null, snapshot);
      await this.plantStore.saveCityRecord(
        this.makeRecordForSave(snapshot, nextPlant, new Date().toISOString(), true)
      );
      this.lastFetchText = this.formatFetchTime();
      this.startAbsorbAnimation(snapshot);
      await this.reloadStoredRecords(true);
      this.statusText = `已重置为第 1/${PLANT_MATURITY_DAYS} 日`;
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    } finally {
      this.loading = false;
      this.rebuildRefreshEligibility();
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
      this.rebuildRefreshEligibility();
    }
  }

  private getErrorMessage(error: Error | Object): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return '暂时无法获取空气质量数据';
  }

  private getRefreshErrorMessage(error: Error | Object): string {
    const message = this.getErrorMessage(error);
    const lowerMessage = message.toLowerCase();
    if (message.indexOf('超时') >= 0 || lowerMessage.indexOf('timeout') >= 0) {
      return 'AQI 更新超时，请检查网络后点击植物重试';
    }
    if (message.indexOf('ApiConfig') >= 0 || lowerMessage.indexOf('token') >= 0 ||
      lowerMessage.indexOf('invalid key') >= 0) {
      return 'AQI 更新失败：WAQI token 缺失或无效';
    }
    if (lowerMessage.indexOf('unknown station') >= 0 || lowerMessage.indexOf('not found') >= 0 ||
      lowerMessage.indexOf('invalid city') >= 0) {
      return 'AQI 更新失败：未找到这个城市的 WAQI 数据';
    }
    if (lowerMessage.indexOf('json') >= 0 || lowerMessage.indexOf('parse') >= 0 ||
      message.indexOf('解析') >= 0) {
      return 'AQI 更新失败：数据解析失败，请稍后点击植物重试';
    }
    if (message.indexOf('WAQI') >= 0) {
      return `AQI 更新失败：${message}`;
    }
    return `AQI 更新失败：${message}`;
  }

  private requestRedraw(): void {
    setTimeout(() => {
      this.drawPlant();
    }, 40);
  }

  private requestAppearancePreviewRedraw(): void {
    setTimeout(() => {
      this.drawAppearancePreview();
    }, 40);
  }

  private requestSharePosterRedraw(): void {
    setTimeout(() => {
      this.drawSharePoster();
    }, 40);
  }

  private formatPosterDateTime(date: Date): string {
    return `${date.getFullYear()}-${this.twoDigits(date.getMonth() + 1)}-${this.twoDigits(date.getDate())} ${this.twoDigits(date.getHours())}:${this.twoDigits(date.getMinutes())}`;
  }

  private getPosterTimeText(): string {
    const snapshot = this.currentSnapshot;
    if (snapshot !== null && snapshot.observedAt.length > 0) {
      return snapshot.observedAt;
    }
    return this.formatPosterDateTime(new Date());
  }

  private getPosterTitle(): string {
    if (this.currentSnapshot === null) {
      return APP_DISPLAY_NAME;
    }
    return `${this.currentSnapshot.cityName} 今日 AQI ${this.getAqiText()}`;
  }

  private getPosterSubTitle(): string {
    if (this.currentSnapshot === null) {
      return '城市空气质量可视化';
    }
    return `AQI ${this.getAqiText()} · ${this.getQualityText()}`;
  }

  private getPosterRadarCommentTitle(): string {
    const snapshot = this.currentSnapshot;
    if (snapshot === null || snapshot.aqi === null) {
      return '空气小札';
    }
    if (snapshot.aqi <= 50) {
      return '雾树舒展';
    }
    if (snapshot.aqi <= 100) {
      return '轻雾经过';
    }
    if (snapshot.aqi <= 150) {
      return '枝叶承压';
    }
    return '今天偏浊';
  }

  private getPosterRadarCommentBody(): string {
    const snapshot = this.currentSnapshot;
    if (snapshot === null) {
      return '等下一次数据抵达，雾树会把城市空气写进叶脉。';
    }
    const dominant = snapshot.dominantPollutant.length === 0 ? '六项指标' :
      this.getPollutantLabel(snapshot.dominantPollutant);
    if (snapshot.aqi === null) {
      return `${dominant} 还在等待完整读数，先看看雷达图的形状。`;
    }
    if (snapshot.aqi <= 50) {
      return `${dominant} 很安静，雾树今天像刚洗过。`;
    }
    if (snapshot.aqi <= 100) {
      return `${dominant} 稍有波动，叶片会收起一点光。`;
    }
    if (snapshot.aqi <= 150) {
      return `${dominant} 正在顶出来，枝端会记住这阵压力。`;
    }
    return `${dominant} 很有存在感，雾树会用灰叶和弯枝提醒你。`;
  }

  private getPollutantLabel(key: string): string {
    if (key === 'pm25') {
      return 'PM2.5';
    }
    if (key === 'pm10') {
      return 'PM10';
    }
    if (key === 'o3') {
      return 'O3';
    }
    if (key === 'no2') {
      return 'NO2';
    }
    if (key === 'so2') {
      return 'SO2';
    }
    return 'CO';
  }

  private getPosterPollutantValue(key: string): number | null {
    if (this.currentSnapshot === null) {
      return null;
    }
    if (key === 'pm25') {
      return this.currentSnapshot.pollutants.pm25;
    }
    if (key === 'pm10') {
      return this.currentSnapshot.pollutants.pm10;
    }
    if (key === 'o3') {
      return this.currentSnapshot.pollutants.o3;
    }
    if (key === 'no2') {
      return this.currentSnapshot.pollutants.no2;
    }
    if (key === 'so2') {
      return this.currentSnapshot.pollutants.so2;
    }
    return this.currentSnapshot.pollutants.co;
  }

  private getAqiAgentQueryText(): string {
    if (this.currentSnapshot === null) {
      return '当前还没有城市 AQI 数据。请问 AQI 是什么呢？';
    }
    const snapshot = this.currentSnapshot;
    const pollutantTexts: string[] = [];
    for (let i = 0; i < POLLUTANT_KEYS.length; i++) {
      const key = POLLUTANT_KEYS[i];
      const value = getPollutantValue(snapshot.pollutants, key);
      pollutantTexts.push(`${this.getPollutantLabel(key)}：${value === null ? '暂无' : value.toFixed(0)}`);
    }
    const aqiText = snapshot.aqi === null ? '暂无' : snapshot.aqi.toFixed(0);
    const observedText = snapshot.observedAt.length === 0 ? '暂无更新时间' : snapshot.observedAt;
    return `现在${snapshot.cityName}的 AQI为${aqiText}，六项 IAQI分别为${pollutantTexts.join('，')}。这样的AQI情况如何呢？`;
  }

  private drawSharePoster(): void {
    this.drawSharePosterPlant();
    this.drawSharePosterRadar();
  }

  private drawSharePosterPlant(): void {
    if (!this.posterPlantReady) {
      return;
    }
    const ctx = this.posterPlantContext;
    const width = SHARE_POSTER_WIDTH - 44;
    const height = SHARE_POSTER_PLANT_HEIGHT;
    ctx.clearRect(0, 0, width, height);
    ctx.fillStyle = '#F5FAF1';
    ctx.fillRect(0, 0, width, height);
    if (!this.hasCityData()) {
      return;
    }

    const plant = normalizePlantState(this.currentPlant);
    const palette = this.plantMorphologyService.buildPaletteForPlant(plant, this.installSeed);
    ctx.fillStyle = palette.background;
    ctx.fillRect(0, 0, width, height);
    this.drawAirParticles(ctx, width, height, plant.particleScore * 0.72, plant.pollutantMemory.pm25 * 0.72,
      plant.pollutantMemory.pm10 * 0.72, 0.4, palette.particle, this.particleWindDirection);

    const virtualWidth = 360;
    const virtualHeight = 560;
    const virtualPotBottom = virtualHeight - 10;
    const scale = Math.min(width / virtualWidth, (height - 10) / virtualPotBottom);
    const offsetX = (width - virtualWidth * scale) / 2;
    const offsetY = height - virtualPotBottom * scale - 4;
    const morphology = this.plantMorphologyService.buildMorphology(
      plant,
      this.installSeed,
      virtualWidth,
      virtualHeight,
      0.6,
      0,
      10,
      0
    );
    ctx.save();
    ctx.translate(offsetX, offsetY);
    ctx.scale(scale, scale);
    this.drawMorphology(ctx, morphology, this.getCurrentPotStyle(), false, false);
    ctx.restore();
    ctx.globalAlpha = 1;
  }

  private drawSharePosterRadar(): void {
    if (!this.posterRadarReady) {
      return;
    }
    const ctx = this.posterRadarContext;
    const width = SHARE_POSTER_RADAR_WIDTH;
    const height = SHARE_POSTER_RADAR_HEIGHT;
    const cx = 70;
    const cy = 66;
    const radius = 39;
    ctx.clearRect(0, 0, width, height);

    ctx.strokeStyle = '#D6E1D5';
    ctx.lineWidth = 1;
    for (let ring = 1; ring <= 4; ring++) {
      const r = radius * ring / 4;
      ctx.beginPath();
      for (let i = 0; i < POLLUTANT_KEYS.length; i++) {
        const angle = -Math.PI / 2 + i * Math.PI * 2 / POLLUTANT_KEYS.length;
        const x = cx + Math.cos(angle) * r;
        const y = cy + Math.sin(angle) * r;
        if (i === 0) {
          ctx.moveTo(x, y);
        } else {
          ctx.lineTo(x, y);
        }
      }
      ctx.closePath();
      ctx.stroke();
    }

    for (let i = 0; i < POLLUTANT_KEYS.length; i++) {
      const angle = -Math.PI / 2 + i * Math.PI * 2 / POLLUTANT_KEYS.length;
      const axisX = cx + Math.cos(angle) * radius;
      const axisY = cy + Math.sin(angle) * radius;
      ctx.strokeStyle = '#DCE6DA';
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.lineTo(axisX, axisY);
      ctx.stroke();

      const labelX = cx + Math.cos(angle) * (radius + 17);
      const labelY = cy + Math.sin(angle) * (radius + 15);
      ctx.fillStyle = '#52625A';
      ctx.font = '14px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(this.getPollutantLabel(POLLUTANT_KEYS[i]), labelX, labelY);
    }

    ctx.beginPath();
    for (let i = 0; i < POLLUTANT_KEYS.length; i++) {
      const key = POLLUTANT_KEYS[i];
      const value = this.getPosterPollutantValue(key);
      const normalized = value === null ? 0 : Math.max(0, Math.min(1, value / 150));
      const angle = -Math.PI / 2 + i * Math.PI * 2 / POLLUTANT_KEYS.length;
      const x = cx + Math.cos(angle) * radius * normalized;
      const y = cy + Math.sin(angle) * radius * normalized;
      if (i === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.closePath();
    ctx.globalAlpha = 0.28;
    ctx.fillStyle = '#4F8A6A';
    ctx.fill();
    ctx.globalAlpha = 1;
    ctx.strokeStyle = '#4F8A6A';
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.globalAlpha = 1;
  }

  private startAbsorbAnimation(snapshot: AqiSnapshot): void {
    this.absorbLevel = this.getAbsorbLevel(snapshot);
    this.absorbFrame = 0;
    this.absorbSeed = Math.floor(Math.random() * 1000000);
    this.absorbActive = true;
  }

  private getAbsorbLevel(snapshot: AqiSnapshot): number {
    let value = 0;
    let hasValue = false;
    if (snapshot.aqi !== null && !isNaN(snapshot.aqi)) {
      value = snapshot.aqi;
      hasValue = true;
    }
    if (!hasValue) {
      let maxPollutant = 0;
      for (let i = 0; i < POLLUTANT_KEYS.length; i++) {
        const pollutantValue = getPollutantValue(snapshot.pollutants, POLLUTANT_KEYS[i]);
        if (pollutantValue !== null && pollutantValue > maxPollutant) {
          maxPollutant = pollutantValue;
        }
      }
      value = maxPollutant;
    }
    if (value <= 50) {
      return 0;
    }
    if (value <= 100) {
      return 1;
    }
    if (value <= 150) {
      return 2;
    }
    return 3;
  }

  private canShareCurrentPoster(): boolean {
    return this.hasCityData() && !this.loading && !this.shareLoading && this.currentSnapshot !== null;
  }

  private shareCurrentPoster(): void {
    if (!this.hasCityData() || this.currentSnapshot === null) {
      this.statusText = '请先选择城市后再分享空气植物海报';
      return;
    }
    if (this.loading || this.shareLoading) {
      return;
    }
    this.shareLoading = true;
    this.statusText = '正在生成空气植物海报';
    this.sharePosterRevision += 1;
    this.requestSharePosterRedraw();
    setTimeout(() => {
      try {
        this.drawSharePoster();
        const picker: SharePicker = new SharePicker({
          title: this.getPosterTitle(),
          subTitle: this.getPosterSubTitle(),
          createTime: new Date().getTime()
        });
        picker.setWindowLayoutFullScreen(true);
        picker.show({
          directPoster: true,
          extComponentId: SHARE_POSTER_COMPONENT_ID,
          sheetTitle: '分享空气植物',
          posterSheetTitle: '分享空气植物海报',
          excludedAbilities: [
            ShareAppType.WECHAT_SESSION,
            ShareAppType.WECHAT_TIMELINE,
            ShareAppType.QQ,
            ShareAppType.WEIBO,
            ShareWay.COPY_TO_PASTEBOARD
          ]
        });
        this.statusText = '海报已生成，可保存图片或使用系统分享';
      } catch (error) {
        this.statusText = '暂时无法生成分享海报';
      } finally {
        this.shareLoading = false;
      }
    }, 160);
  }

  private async handlePlantTap(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.rebuildRefreshEligibility();
    if (this.shouldRefreshCurrentCityOnTap()) {
      this.statusText = '正在更新本小时空气数据';
      await this.refreshCurrentFromNetwork();
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

  private async openGuideDetail(): Promise<void> {
    try {
      await router.pushUrl({ url: 'pages/GuideDetail' });
    } catch (error) {
      this.statusText = '暂时无法打开说明页面';
    }
  }

  private selectPlantSpecies(species: PlantSpeciesId): void {
    if (species !== 'mistTree') {
      return;
    }
    this.selectedPlantSpecies = species;
    this.requestAppearancePreviewRedraw();
  }

  private selectPotStyle(style: PotStyleId): void {
    this.selectedPotStyle = style;
    this.requestAppearancePreviewRedraw();
  }

  private async confirmAppearanceSelection(): Promise<void> {
    const record = this.getCurrentRecord();
    if (record === null || this.loading) {
      return;
    }
    this.loading = true;
    try {
      await this.plantStore.saveCityAppearance(record.cityKey, this.selectedPlantSpecies, this.selectedPotStyle);
      this.showAppearancePicker = false;
      await this.reloadStoredRecords(true);
      this.statusText = '植物与花盆已固定，开始记录这座城市的空气记忆';
      this.requestRedraw();
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    } finally {
      this.loading = false;
      this.rebuildRefreshEligibility();
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
    return getPlantGrowthStageText(this.currentPlant);
  }

  private getPlantMoodLabel(): string {
    return `${this.getPlantSpeciesName(this.selectedPlantSpecies)}·${this.getPlantMoodText().split(' ').join('')}`;
  }

  private getQualityColorValue(): string {
    if (this.currentSnapshot === null) {
      return '#587064';
    }
    return getQualityColor(this.currentSnapshot.aqi);
  }

  private getAqiPulseScale(): number {
    if (!this.absorbActive || this.absorbFrame <= 0) {
      return 1;
    }
    const progress = Math.min(1, this.absorbFrame / ABSORB_ANIMATION_DURATION);
    const wave = Math.sin(progress * Math.PI);
    return 1 + wave * (0.02 + this.absorbLevel * 0.018);
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

  private getPlantStageBackgroundColor(): string {
    if (!this.hasCityData()) {
      return '#EEF4E8';
    }
    return this.plantMorphologyService.buildPaletteForPlant(
      normalizePlantState(this.currentPlant),
      this.installSeed
    ).background;
  }

  private isPhoneDevice(): boolean {
    return `${deviceInfo.deviceType}`.toLowerCase() === 'phone';
  }

  private isCompactTopBar(): boolean {
    const isNarrowWindow: boolean = this.viewportWidth > 0 && this.viewportWidth <= 520;
    return this.isPhoneDevice() || isNarrowWindow;
  }

  private getPlantInfoTopPadding(): number {
    if (this.isCompactTopBar()) {
      return this.isTestCity() ? (this.testEditorExpanded ? 398 : 196) : 130;
    }
    if (!this.isTestCity()) {
      return 88;
    }
    return this.testEditorExpanded ? 356 : 154;
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

  private hasRefreshErrorStatus(): boolean {
    return this.statusText.indexOf('AQI 更新失败') >= 0 || this.statusText.indexOf('AQI 更新超时') >= 0 ||
      this.statusText.indexOf('WAQI token') >= 0;
  }

  private getStageHintText(): string {
    const hintRevision = this.refreshHintRevision;
    if (hintRevision < 0) {
      return this.statusText;
    }
    if (this.loading || this.currentSnapshot === null) {
      return this.statusText;
    }
    if (this.hasRefreshErrorStatus()) {
      return this.statusText;
    }
    if (!this.isTestCity() && !this.aqiClient.hasToken()) {
      return '配置 WAQI token 后可更新数据';
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
    this.drawAirParticles(ctx, width, height, plant.particleScore, plant.pollutantMemory.pm25,
      plant.pollutantMemory.pm10, time, palette.particle, this.getParticleWindDirection());

    if (Math.abs(this.plantDragOffsetX) > 0.5) {
      const dragOffset = this.plantDragOffsetX;
      const targetIndex = this.getDragTargetIndex(dragOffset);
      const hasTarget = targetIndex >= 0 && targetIndex < this.cityRecords.length;
      const currentOffset = hasTarget ? dragOffset : dragOffset * 0.28;
      this.drawPlantBody(ctx, plant, width, height, time, currentOffset, this.touchPulse, this.getCurrentPotStyle(), false);
      if (hasTarget) {
        const enteringPlant = normalizePlantState(this.cityRecords[targetIndex].plant);
        const enteringOffset = dragOffset < 0 ? width + dragOffset : -width + dragOffset;
        this.drawPlantBody(ctx, enteringPlant, width, height, time, enteringOffset, 0,
          this.cityRecords[targetIndex].potStyle, false);
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
        0,
        this.transitionPreviousPotStyle,
        false
      );
      this.drawPlantBody(
        ctx,
        plant,
        width,
        height,
        time,
        -(1 - eased) * width * this.plantSlideDirection,
        this.touchPulse,
        this.getCurrentPotStyle(),
        false
      );
      return;
    }

    if (this.plantSlideProgress >= 1) {
      this.transitionPreviousPlant = null;
    }
    this.drawPlantBody(ctx, plant, width, height, time, 0, this.touchPulse, this.getCurrentPotStyle(), true);
  }

  private drawPlantBody(
    ctx: CanvasRenderingContext2D,
    plant: PlantState,
    width: number,
    height: number,
    time: number,
    offsetX: number,
    pulse: number,
    potStyle: PotStyleId,
    allowAbsorb: boolean
  ): void {
    const morphology = this.plantMorphologyService.buildMorphology(
      plant,
      this.installSeed,
      width,
      height,
      time,
      offsetX,
      this.detailLayoutProgress * this.getDetailPanelHeight(),
      pulse
    );
    this.drawMorphology(ctx, morphology, potStyle, allowAbsorb, true);
  }

  private createAppearancePreviewPlant(): PlantState {
    const plant = createInitialPlantState('mist_tree_preview', '雾树样本');
    plant.sampleCount = PLANT_MATURITY_DAYS;
    plant.lastObservedAt = '2026-05-14T08:00:00+08:00';
    plant.observationDates = [
      '2026-05-01',
      '2026-05-02',
      '2026-05-03',
      '2026-05-04',
      '2026-05-05',
      '2026-05-06',
      '2026-05-07',
      '2026-05-08',
      '2026-05-09',
      '2026-05-10',
      '2026-05-11',
      '2026-05-12',
      '2026-05-13',
      '2026-05-14'
    ];
    plant.averageStress = 0.14;
    plant.pollutantMemory.pm25 = 0.10;
    plant.pollutantMemory.pm10 = 0.10;
    plant.pollutantMemory.o3 = 0.10;
    plant.pollutantMemory.no2 = 0.08;
    plant.pollutantMemory.so2 = 0.06;
    plant.pollutantMemory.co = 0.06;
    plant.lifetimePollutantMemory = plant.pollutantMemory;
    plant.heightScore = 0.92;
    plant.leafScore = 0.90;
    plant.colorScore = 0.92;
    plant.droopScore = 0.05;
    plant.bloomScore = 0.78;
    plant.particleScore = 0.05;
    return normalizePlantState(plant);
  }

  private drawAppearancePreview(): void {
    if (!this.appearancePreviewReady) {
      return;
    }
    const ctx = this.appearancePreviewContext;
    const width = Math.max(220, this.appearancePreviewWidth);
    const height = Math.max(180, this.appearancePreviewHeight);
    const virtualWidth = 360;
    const virtualHeight = 720;
    const scale = Math.min(width / virtualWidth, height / virtualHeight) * 0.94;
    const offsetX = (width - virtualWidth * scale) / 2;
    const offsetY = (height - virtualHeight * scale) / 2 + 4;
    const previewPlant = this.createAppearancePreviewPlant();
    const morphology = this.plantMorphologyService.buildMorphology(
      previewPlant,
      'appearance_preview_seed',
      virtualWidth,
      virtualHeight,
      this.animationFrame * 0.10,
      0,
      0,
      0
    );
    ctx.clearRect(0, 0, width, height);
    ctx.fillStyle = '#F4F8F0';
    ctx.fillRect(0, 0, width, height);
    ctx.save();
    ctx.translate(offsetX, offsetY);
    ctx.scale(scale, scale);
    this.drawMorphology(ctx, morphology, this.selectedPotStyle, false, false);
    ctx.restore();
    ctx.globalAlpha = 1;
  }

  private drawMorphology(
    ctx: CanvasRenderingContext2D,
    morphology: PlantMorphology,
    potStyle: PotStyleId,
    allowAbsorb: boolean,
    allowLeafBurst: boolean
  ): void {
    this.drawMorphSoil(ctx, morphology, potStyle);

    const plantOffsetY = this.getPotPlantOffsetY(potStyle);
    if (plantOffsetY !== 0) {
      ctx.save();
      ctx.translate(0, plantOffsetY);
    }

    for (let i = 0; i < morphology.branches.length; i++) {
      this.drawMorphBranch(ctx, morphology.branches[i], morphology.palette.lesion);
    }

    for (let i = 0; i < morphology.leaves.length; i++) {
      this.drawMorphLeaf(ctx, morphology.leaves[i], morphology.palette.lesion);
    }

    for (let i = 0; i < morphology.buds.length; i++) {
      this.drawMorphBud(ctx, morphology.buds[i]);
    }
    if (allowLeafBurst && this.leafBurstActive) {
      this.drawLeafBurst(ctx, morphology);
    }
    if (allowAbsorb && this.absorbActive) {
      this.drawAbsorbAnimation(ctx, morphology);
    }
    if (plantOffsetY !== 0) {
      ctx.restore();
    }
    ctx.globalAlpha = 1;
  }

  private getPotPlantOffsetY(potStyle: PotStyleId): number {
    if (potStyle === 'mistCeramic') {
      return -18;
    }
    return 0;
  }

  private drawMorphSoil(ctx: CanvasRenderingContext2D, morphology: PlantMorphology, potStyle: PotStyleId): void {
    const rootX = morphology.rootX;
    const potBottom = morphology.potBottomY;
    const soilY = morphology.rootY;

    if (potStyle === 'shallowStone') {
      const bodyTop = soilY + 5;
      ctx.fillStyle = '#C8CED0';
      this.drawBottomRoundRect(ctx, rootX - 72, bodyTop, 144, potBottom - bodyTop, 5);

      ctx.strokeStyle = '#A7B0B3';
      ctx.lineWidth = 1.1;
      for (let i = 0; i < 3; i++) {
        const stripeY = bodyTop + 12 + i * 10;
        ctx.beginPath();
        ctx.moveTo(rootX - 62, stripeY);
        ctx.lineTo(rootX + 62, stripeY);
        ctx.stroke();
      }

      ctx.strokeStyle = '#DDE1E2';
      ctx.lineWidth = 1.3;
      ctx.beginPath();
      ctx.moveTo(rootX - 46, bodyTop + 4);
      ctx.lineTo(rootX + 46, bodyTop + 4);
      ctx.stroke();

      ctx.fillStyle = '#D9DEDE';
      this.drawRoundRect(ctx, rootX - 72, soilY - 8, 144, 16, 2);

      ctx.fillStyle = '#5C5244';
      this.drawRoundRect(ctx, rootX - 60, soilY - 5, 120, 10, 3);

      ctx.strokeStyle = '#8D9699';
      ctx.lineWidth = 1.6;
      ctx.beginPath();
      ctx.moveTo(rootX - 61, soilY - 5);
      ctx.lineTo(rootX + 61, soilY - 5);
      ctx.lineTo(rootX + 61, soilY + 5);
      ctx.lineTo(rootX - 61, soilY + 5);
      ctx.closePath();
      ctx.stroke();
      return;
    }

    if (potStyle === 'mistCeramic') {
      const mouthY = soilY - 18;
      const bodyTop = mouthY;

      ctx.globalAlpha = 0.62;
      ctx.fillStyle = '#5D4B35';
      ctx.beginPath();
      ctx.moveTo(rootX - 51, mouthY);
      ctx.lineTo(rootX + 51, mouthY);
      ctx.lineTo(rootX + 50, potBottom - 24);
      ctx.quadraticCurveTo(rootX + 41, potBottom - 12, rootX + 27, potBottom - 10);
      ctx.quadraticCurveTo(rootX + 11, potBottom - 17, rootX, potBottom - 13);
      ctx.quadraticCurveTo(rootX - 11, potBottom - 17, rootX - 27, potBottom - 10);
      ctx.quadraticCurveTo(rootX - 41, potBottom - 12, rootX - 50, potBottom - 24);
      ctx.closePath();
      ctx.fill();
      ctx.globalAlpha = 1;

      ctx.globalAlpha = 0.72;
      ctx.fillStyle = '#48A95E';
      ctx.beginPath();
      ctx.moveTo(rootX - 56, bodyTop);
      ctx.lineTo(rootX - 58, potBottom - 18);
      ctx.quadraticCurveTo(rootX - 49, potBottom - 2, rootX - 31, potBottom - 1);
      ctx.quadraticCurveTo(rootX - 18, potBottom - 9, rootX, potBottom - 4);
      ctx.quadraticCurveTo(rootX + 18, potBottom - 9, rootX + 31, potBottom - 1);
      ctx.quadraticCurveTo(rootX + 49, potBottom - 2, rootX + 58, potBottom - 18);
      ctx.lineTo(rootX + 56, bodyTop);
      ctx.closePath();
      ctx.fill();
      ctx.globalAlpha = 1;

      ctx.strokeStyle = '#79C886';
      ctx.lineWidth = 1.1;
      for (let i = -2; i <= 2; i++) {
        const offset = i * 17;
        ctx.beginPath();
        ctx.moveTo(rootX + offset, bodyTop + 7);
        ctx.quadraticCurveTo(rootX + offset * 0.96, bodyTop + 32, rootX + offset * 0.82, potBottom - 15);
        ctx.stroke();
      }

      ctx.strokeStyle = '#A6E0A5';
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.moveTo(rootX - 53, mouthY);
      ctx.lineTo(rootX + 53, mouthY);
      ctx.stroke();
      ctx.globalAlpha = 1;
      return;
    }

    const boxTop = soilY + 8;
    const boxLeft = rootX - 74;
    const boxWidth = 148;
    const boxHeight = potBottom - boxTop;
    const backY = soilY - 14;
    const frontY = boxTop;
    const backLeftX = rootX - 62;
    const backRightX = rootX + 62;
    const frontLeftX = rootX - 74;
    const frontRightX = rootX + 74;
    ctx.fillStyle = '#A99571';
    ctx.fillRect(boxLeft, boxTop, boxWidth, boxHeight);

    ctx.fillStyle = '#C4B088';
    ctx.beginPath();
    ctx.moveTo(backLeftX, backY);
    ctx.lineTo(frontLeftX, frontY);
    ctx.lineTo(frontLeftX - 36, frontY + 22);
    ctx.lineTo(backLeftX - 28, backY + 16);
    ctx.closePath();
    ctx.fill();

    ctx.beginPath();
    ctx.moveTo(backRightX, backY);
    ctx.lineTo(frontRightX, frontY);
    ctx.lineTo(frontRightX + 36, frontY + 22);
    ctx.lineTo(backRightX + 28, backY + 16);
    ctx.closePath();
    ctx.fill();

    ctx.fillStyle = '#B8A27A';
    ctx.beginPath();
    ctx.moveTo(backLeftX, backY);
    ctx.lineTo(backRightX, backY);
    ctx.lineTo(frontRightX, frontY);
    ctx.lineTo(frontLeftX, frontY);
    ctx.closePath();
    ctx.fill();

    ctx.fillStyle = '#6C573E';
    ctx.beginPath();
    ctx.moveTo(backLeftX, backY + 7);
    ctx.lineTo(backRightX, backY + 7);
    ctx.lineTo(frontRightX - 4, frontY);
    ctx.lineTo(frontLeftX + 4, frontY);
    ctx.closePath();
    ctx.fill();

    ctx.strokeStyle = '#7E6F55';
    ctx.lineWidth = 0.7;
    ctx.beginPath();
    ctx.moveTo(backLeftX, backY);
    ctx.lineTo(backLeftX, backY + 7);
    ctx.moveTo(backRightX, backY);
    ctx.lineTo(backRightX, backY + 7);
    ctx.stroke();

    ctx.strokeStyle = '#6F6046';
    ctx.lineWidth = 1.6;
    ctx.beginPath();
    ctx.moveTo(rootX - 46, boxTop + 26);
    ctx.lineTo(rootX - 20, boxTop + 26);
    ctx.lineTo(rootX - 20, boxTop + 39);
    ctx.lineTo(rootX - 46, boxTop + 39);
    ctx.closePath();
    ctx.moveTo(rootX + 28, boxTop + 31);
    ctx.lineTo(rootX + 49, boxTop + 31);
    ctx.lineTo(rootX + 42, boxTop + 25);
    ctx.moveTo(rootX + 49, boxTop + 31);
    ctx.lineTo(rootX + 42, boxTop + 37);
    ctx.stroke();
  }

  private drawBottomRoundRect(
    ctx: CanvasRenderingContext2D,
    x: number,
    y: number,
    width: number,
    height: number,
    radius: number
  ): void {
    const r = Math.max(0, Math.min(radius, Math.min(width, height) / 2));
    const right = x + width;
    const bottom = y + height;
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(right, y);
    ctx.lineTo(right, bottom - r);
    ctx.quadraticCurveTo(right, bottom, right - r, bottom);
    ctx.lineTo(x + r, bottom);
    ctx.quadraticCurveTo(x, bottom, x, bottom - r);
    ctx.lineTo(x, y);
    ctx.closePath();
    ctx.fill();
  }

  private drawRoundRect(
    ctx: CanvasRenderingContext2D,
    x: number,
    y: number,
    width: number,
    height: number,
    radius: number
  ): void {
    const r = Math.max(0, Math.min(radius, Math.min(width, height) / 2));
    const right = x + width;
    const bottom = y + height;
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.lineTo(right - r, y);
    ctx.quadraticCurveTo(right, y, right, y + r);
    ctx.lineTo(right, bottom - r);
    ctx.quadraticCurveTo(right, bottom, right - r, bottom);
    ctx.lineTo(x + r, bottom);
    ctx.quadraticCurveTo(x, bottom, x, bottom - r);
    ctx.lineTo(x, y + r);
    ctx.quadraticCurveTo(x, y, x + r, y);
    ctx.closePath();
    ctx.fill();
  }

  private drawAbsorbAnimation(ctx: CanvasRenderingContext2D, morphology: PlantMorphology): void {
    const progress = Math.min(1, this.absorbFrame / ABSORB_ANIMATION_DURATION);
    const easeIn = progress * progress;
    const fadeOut = Math.max(0, 1 - progress);
    const rootX = morphology.rootX;
    const rootY = morphology.rootY - 2;
    let count = 46;
    let primaryColor = '#91DDBB';
    let secondaryColor = '#A9DCEB';
    let glowAlpha = 0.34;
    let spread = 138;
    if (this.absorbLevel === 1) {
      count = 74;
      primaryColor = '#C8D36C';
      secondaryColor = '#E5D77A';
      glowAlpha = 0.44;
      spread = 176;
    } else if (this.absorbLevel === 2) {
      count = 104;
      primaryColor = '#C4A55B';
      secondaryColor = '#878271';
      glowAlpha = 0.56;
      spread = 214;
    } else if (this.absorbLevel >= 3) {
      count = 138;
      primaryColor = '#7C6666';
      secondaryColor = '#B84D5A';
      glowAlpha = 0.68;
      spread = 258;
    }

    ctx.globalAlpha = glowAlpha * fadeOut;
    ctx.fillStyle = secondaryColor;
    ctx.beginPath();
    ctx.ellipse(rootX, rootY, 48 + spread * easeIn, 16 + 30 * easeIn, 0, 0, Math.PI * 2);
    ctx.fill();
    for (let ring = 0; ring < 4; ring++) {
      const ringProgress = Math.max(0, Math.min(1, progress * 1.15 - ring * 0.18));
      ctx.globalAlpha = glowAlpha * (1 - ringProgress) * (0.42 - ring * 0.07);
      ctx.strokeStyle = ring % 2 === 0 ? primaryColor : secondaryColor;
      ctx.lineWidth = 1.7 + this.absorbLevel * 0.8;
      ctx.beginPath();
      ctx.ellipse(rootX, rootY, 28 + spread * ringProgress, 10 + 24 * ringProgress, 0, 0, Math.PI * 2);
      ctx.stroke();
    }
    for (let i = 0; i < count; i++) {
      const n1 = this.absorbNoise(i, 1);
      const n2 = this.absorbNoise(i, 2);
      const n3 = this.absorbNoise(i, 3);
      const startX = rootX + (n1 - 0.5) * (spread * 2.2);
      const startY = rootY - 210 - n2 * 340;
      const targetX = rootX + (n2 - 0.5) * 44;
      const targetY = rootY - n3 * 20;
      const sway = Math.sin(progress * 10 + i * 0.78) * (14 + this.absorbLevel * 6);
      const x = startX + (targetX - startX) * easeIn + sway;
      const y = startY + (targetY - startY) * easeIn;
      const radius = 3.0 + n3 * 4.2 + this.absorbLevel * 0.9;
      ctx.globalAlpha = fadeOut * (0.42 + n2 * 0.60);
      ctx.fillStyle = i % 2 === 0 ? primaryColor : secondaryColor;
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.fill();
    }
    const burstCount = 16 + this.absorbLevel * 8;
    for (let i = 0; i < burstCount; i++) {
      const n1 = this.absorbNoise(i, 6);
      const n2 = this.absorbNoise(i, 7);
      const angle = n1 * Math.PI * 2;
      const distance = (18 + spread * 0.22) * Math.sin(progress * Math.PI) * (0.45 + n2 * 0.75);
      const x = rootX + Math.cos(angle) * distance;
      const y = rootY + Math.sin(angle) * distance * 0.32;
      ctx.globalAlpha = fadeOut * (0.22 + n2 * 0.38);
      ctx.fillStyle = n1 > 0.5 ? primaryColor : secondaryColor;
      ctx.beginPath();
      ctx.arc(x, y, 2.2 + n2 * 3.4 + this.absorbLevel * 0.55, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  private absorbNoise(index: number, salt: number): number {
    const raw = Math.sin((index + 1) * 19.9898 + salt * 67.233 + this.absorbSeed * 0.013 +
      this.currentCityIndex * 31.719) * 43758.5453;
    return raw - Math.floor(raw);
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

    if (branch.scar > 0.20) {
      const scarX = (branch.startX + branch.controlX + branch.endX) / 3;
      const scarY = (branch.startY + branch.controlY + branch.endY) / 3;
      ctx.globalAlpha = Math.min(0.62, branch.scar);
      ctx.strokeStyle = lesionColor;
      ctx.lineWidth = Math.max(1.2, branch.width * (0.30 + branch.twist * 0.16));
      ctx.beginPath();
      ctx.moveTo(scarX - branch.width * 1.2, scarY - branch.width * 0.6);
      ctx.lineTo(scarX + branch.width * 1.5, scarY + branch.width * 0.7);
      ctx.stroke();
    }
    if (branch.twist > 0.38) {
      const tipScarX = branch.endX * 0.76 + branch.controlX * 0.24;
      const tipScarY = branch.endY * 0.76 + branch.controlY * 0.24;
      ctx.globalAlpha = Math.min(0.42, branch.twist * 0.52);
      ctx.strokeStyle = lesionColor;
      ctx.lineWidth = Math.max(0.9, branch.width * 0.22);
      ctx.beginPath();
      ctx.moveTo(tipScarX - branch.width * 1.6, tipScarY + branch.width * 0.4);
      ctx.lineTo(tipScarX + branch.width * 1.6, tipScarY - branch.width * 0.5);
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
    if (leaf.bleach > 0.22) {
      ctx.globalAlpha = Math.min(0.36, leaf.bleach * 0.42);
      ctx.fillStyle = '#E9E5C7';
      ctx.beginPath();
      ctx.ellipse(midX - px * leaf.width * 0.10, midY - py * leaf.width * 0.10,
        Math.max(1, leaf.width * 0.38), Math.max(1, leaf.length * 0.13), 0, 0, Math.PI * 2);
      ctx.fill();
    }
    if (leaf.dust > 0.20) {
      ctx.fillStyle = '#6F695E';
      const dustCount = leaf.dust > 0.66 ? 4 : (leaf.dust > 0.42 ? 3 : 2);
      for (let i = 0; i < dustCount; i++) {
        const dustNoise = this.leafNoise(leaf, i);
        const dustProgress = 0.24 + i * 0.16 + dustNoise * 0.08;
        const dustSide = (dustNoise - 0.5) * leaf.width * 1.35;
        const dustX = leaf.rootX + ux * leaf.length * dustProgress + px * dustSide;
        const dustY = leaf.rootY + uy * leaf.length * dustProgress + py * dustSide;
        ctx.globalAlpha = Math.min(0.32, leaf.dust * (0.20 + dustNoise * 0.24));
        ctx.beginPath();
        ctx.ellipse(dustX, dustY, Math.max(0.8, leaf.width * 0.12), Math.max(0.7, leaf.width * 0.08),
          0, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    if (leaf.edgeBurn > 0.24) {
      ctx.globalAlpha = Math.min(0.42, leaf.edgeBurn * 0.46);
      ctx.strokeStyle = lesionColor;
      ctx.lineWidth = Math.max(0.8, leaf.width * 0.12);
      ctx.beginPath();
      ctx.moveTo(midX + px * leftWidth * 0.82, midY + py * leftWidth * 0.82);
      ctx.quadraticCurveTo(midX + px * leftWidth * 0.30, midY + py * leftWidth * 0.30, tipX, tipY);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }

  private leafNoise(leaf: MorphLeaf, salt: number): number {
    const raw = Math.sin(leaf.rootX * 0.173 + leaf.rootY * 0.211 + leaf.length * 0.071 + salt * 19.19) * 43758.5453;
    return raw - Math.floor(raw);
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

  private particleNoise(index: number, salt: number): number {
    const raw = Math.sin((index + 1) * 31.417 + salt * 93.133 + this.currentCityIndex * 19.719 +
      this.installSeed.length * 0.271) * 43758.5453;
    return raw - Math.floor(raw);
  }

  private getParticleWindDirection(): number {
    if (Math.abs(this.plantDragOffsetX) > 0.5) {
      return this.plantDragOffsetX < 0 ? -1 : 1;
    }
    if (this.transitionPreviousPlant !== null && this.plantSlideProgress < 1) {
      return this.plantSlideDirection;
    }
    return this.particleWindDirection;
  }

  private wrapParticleCoordinate(value: number, min: number, max: number): number {
    const range = max - min;
    if (range <= 0) {
      return min;
    }
    let wrapped = (value - min) % range;
    if (wrapped < 0) {
      wrapped += range;
    }
    return min + wrapped;
  }

  private drawAirParticles(
    ctx: CanvasRenderingContext2D,
    width: number,
    height: number,
    stress: number,
    fineHaze: number,
    coarseDust: number,
    time: number,
    color: string,
    windDirection: number
  ): void {
    const direction = windDirection < 0 ? -1 : 1;
    const fineCount = Math.round(12 + stress * 24 + fineHaze * 52);
    ctx.fillStyle = color;
    for (let i = 0; i < fineCount; i++) {
      const baseX = 16 + this.particleNoise(i, 1.7) * (width - 32);
      const baseY = 20 + this.particleNoise(i, 4.9) * (height - 142);
      const wind = (time * (9 + fineHaze * 18 + this.particleNoise(i, 6.3) * 12) +
        this.particleNoise(i, 7.4) * width) * direction;
      const driftX = Math.sin(time * (0.32 + this.particleNoise(i, 8.1) * 0.36) + i * 1.91) *
        (3 + fineHaze * 6);
      const driftY = Math.cos(time * (0.20 + this.particleNoise(i, 10.4) * 0.28) + i * 1.27) *
        (2 + stress * 5);
      const x = this.wrapParticleCoordinate(baseX + wind + driftX, -12, width + 12);
      const y = baseY + driftY;
      const radius = 0.7 + stress * 1.4 + fineHaze * 1.7 + this.particleNoise(i, 12.8) * 1.5;
      ctx.globalAlpha = 0.07 + stress * 0.14 + fineHaze * 0.22 + this.particleNoise(i, 15.2) * 0.08;
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.fill();
    }
    const coarseCount = Math.round(stress * 5 + coarseDust * 34);
    ctx.fillStyle = '#7A7164';
    for (let i = 0; i < coarseCount; i++) {
      const baseX = 20 + this.particleNoise(i, 21.3) * (width - 40);
      const baseY = 38 + this.particleNoise(i, 24.6) * (height - 180);
      const wind = (time * (6 + coarseDust * 14 + this.particleNoise(i, 26.2) * 9) +
        this.particleNoise(i, 27.1) * width) * direction;
      const driftX = Math.sin(time * (0.24 + this.particleNoise(i, 28.9) * 0.26) + i * 1.11) *
        (3 + coarseDust * 7);
      const driftY = Math.cos(time * (0.18 + this.particleNoise(i, 31.7) * 0.18) + i * 1.57) *
        (3 + coarseDust * 7);
      const x = this.wrapParticleCoordinate(baseX + wind + driftX, -14, width + 14);
      const y = baseY + driftY;
      const radius = 1.6 + coarseDust * 4.0 + this.particleNoise(i, 35.5) * 2.4;
      ctx.globalAlpha = 0.10 + coarseDust * 0.28 + this.particleNoise(i, 38.2) * 0.10;
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  private getPlantSpeciesName(species: PlantSpeciesId): string {
    if (species === 'floatingFern') {
      return '浮蕨';
    }
    if (species === 'murkyRoot') {
      return '浊根';
    }
    return '雾树';
  }

  private getPotStyleName(style: PotStyleId): string {
    if (style === 'mistCeramic') {
      return '雾绿瓶盆';
    }
    if (style === 'darkSlate') {
      return '纸浆方盒盆';
    }
    return '再生铝罐盆';
  }

  private getPotStyleColor(style: PotStyleId): string {
    if (style === 'mistCeramic') {
      return '#48A95E';
    }
    if (style === 'darkSlate') {
      return '#9A987F';
    }
    return '#C8CED0';
  }

  private getPotStyleRimColor(style: PotStyleId): string {
    if (style === 'mistCeramic') {
      return '#2C8B4D';
    }
    if (style === 'darkSlate') {
      return '#7F806A';
    }
    return '#D9DEDE';
  }

  private getPotStyleAccentColor(style: PotStyleId): string {
    if (style === 'mistCeramic') {
      return '#79C886';
    }
    if (style === 'darkSlate') {
      return '#7E806A';
    }
    return '#A7B0B3';
  }

  @Builder
  PotMiniPreview(style: PotStyleId) {
    Column({ space: 0 }) {
      Blank()
        .layoutWeight(1)
      if (style === 'shallowStone') {
        Column({ space: 4 }) {
          Blank()
            .width(64)
            .height(2)
            .backgroundColor(this.getPotStyleAccentColor(style))
            .borderRadius(1)
          Blank()
            .width(66)
            .height(2)
            .backgroundColor(this.getPotStyleAccentColor(style))
            .borderRadius(1)
          Blank()
            .width(62)
            .height(2)
            .backgroundColor(this.getPotStyleAccentColor(style))
            .borderRadius(1)
        }
        .width(82)
        .height(24)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.getPotStyleColor(style))
        .borderRadius(3)
      } else if (style === 'mistCeramic') {
        Column({ space: 0 }) {
          Row({ space: 10 }) {
            Blank()
              .width(2)
              .height(33)
              .backgroundColor(this.getPotStyleAccentColor(style))
              .borderRadius(1)
            Blank()
              .width(2)
              .height(37)
              .backgroundColor(this.getPotStyleAccentColor(style))
              .borderRadius(1)
            Blank()
              .width(2)
              .height(37)
              .backgroundColor(this.getPotStyleAccentColor(style))
              .borderRadius(1)
            Blank()
              .width(2)
              .height(33)
              .backgroundColor(this.getPotStyleAccentColor(style))
              .borderRadius(1)
          }
          .height(37)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          Row({ space: 5 }) {
            Blank()
              .width(13)
              .height(6)
              .backgroundColor(this.getPotStyleRimColor(style))
              .borderRadius(4)
            Blank()
              .width(13)
              .height(6)
              .backgroundColor(this.getPotStyleRimColor(style))
              .borderRadius(4)
            Blank()
              .width(13)
              .height(6)
              .backgroundColor(this.getPotStyleRimColor(style))
              .borderRadius(4)
          }
          .height(7)
          .justifyContent(FlexAlign.Center)
        }
        .width(68)
        .height(48)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.getPotStyleColor(style))
        .borderRadius(9)
      } else {
        Column({ space: 5 }) {
          Blank()
            .width(44)
            .height(2)
            .backgroundColor(this.getPotStyleAccentColor(style))
          Row({ space: 6 }) {
            Blank()
              .width(17)
              .height(10)
              .backgroundColor('#B7A27A')
            Blank()
              .width(24)
              .height(2)
              .backgroundColor(this.getPotStyleAccentColor(style))
            Blank()
              .width(9)
              .height(2)
              .backgroundColor(this.getPotStyleAccentColor(style))
          }
          .justifyContent(FlexAlign.Center)
        }
        .width(82)
        .height(34)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.getPotStyleColor(style))
      }
    }
    .width('100%')
    .height(62)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  PlantChoiceCard(species: PlantSpeciesId, enabled: boolean) {
    Column({ space: 5 }) {
      Text(this.getPlantSpeciesName(species))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(enabled ? '#26312B' : '#8D958F')
      Text(enabled ? '当前可选' : '未来计划')
        .fontSize(11)
        .fontColor(enabled ? '#51735F' : '#9AA39D')
    }
    .width('31%')
    .height(72)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(enabled ? '#FFFFFF' : '#EEF1ED')
    .borderRadius(12)
    .border({
      width: this.selectedPlantSpecies === species ? 2 : 1,
      color: this.selectedPlantSpecies === species ? '#4F8A6A' : '#DCE4DC'
    })
    .opacity(enabled ? 1 : 0.68)
    .onClick(() => {
      this.selectPlantSpecies(species);
    })
  }

  @Builder
  PotChoiceCard(style: PotStyleId) {
    Column({ space: 4 }) {
      this.PotMiniPreview(style)
      Text(this.getPotStyleName(style))
        .fontSize(12)
        .fontColor('#314039')
    }
    .width('31%')
    .height(96)
    .padding({ left: 6, right: 6, top: 8, bottom: 8 })
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .border({
      width: this.selectedPotStyle === style ? 2 : 1,
      color: this.selectedPotStyle === style ? '#4F8A6A' : '#DCE4DC'
    })
    .onClick(() => {
      this.selectPotStyle(style);
    })
  }

  @Builder
  AppearancePickerOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        Blank()
      }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')

      Column({ space: 14 }) {
        Column({ space: 3 }) {
          Text('选择这座城市的植物')
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor('#24312B')
          Text('创建后将固定外观，空气数据会继续改变它的生长状态。')
            .fontSize(12)
            .fontColor('#66726C')
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)

        Canvas(this.appearancePreviewContext)
          .width('100%')
          .height(236)
          .backgroundColor('#F4F8F0')
          .borderRadius(12)
          .onAreaChange((oldValue, newValue) => {
            const nextWidth = Number(newValue.width);
            if (!isNaN(nextWidth) && nextWidth > 0) {
              this.appearancePreviewWidth = nextWidth;
            }
            const nextHeight = Number(newValue.height);
            if (!isNaN(nextHeight) && nextHeight > 0) {
              this.appearancePreviewHeight = nextHeight;
            }
            this.requestAppearancePreviewRedraw();
          })
          .onReady(() => {
            this.appearancePreviewReady = true;
            this.drawAppearancePreview();
          })

        Row({ space: 8 }) {
          this.PlantChoiceCard('mistTree', true)
          this.PlantChoiceCard('floatingFern', false)
          this.PlantChoiceCard('murkyRoot', false)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        Row({ space: 8 }) {
          this.PotChoiceCard('shallowStone')
          this.PotChoiceCard('mistCeramic')
          this.PotChoiceCard('darkSlate')
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        Button(this.loading ? '保存中' : '确认外观')
          .width('100%')
          .height(44)
          .fontSize(15)
          .enabled(!this.loading)
          .backgroundColor('#3F715D')
          .borderRadius(12)
          .onClick(() => {
            this.confirmAppearanceSelection();
          })
      }
      .width('88%')
      .constraintSize({ maxWidth: 520 })
      .padding({ left: 18, right: 18, top: 18, bottom: 18 })
      .backgroundColor('#FAFCF7')
      .borderRadius(18)
      .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 8 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  AqiSharePosterSnapshot() {
    Column({ space: 9 }) {
      Row() {
        Column({ space: 3 }) {
          Text(APP_DISPLAY_NAME)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getPlantAccentColor())
          Text(this.getPosterTimeText())
            .fontSize(11)
            .fontColor('#6F7B72')
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 2 }) {
          Text(this.getCityName())
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor('#22302A')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.getCollectedDaysText())
            .fontSize(10)
            .fontColor('#6F7B72')
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 12 }) {
        Column({ space: 0 }) {
          Text('今日 AQI')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#66726D')
          Text(this.getAqiText())
            .fontSize(58)
            .lineHeight(62)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getQualityColorValue())
        }
        .alignItems(HorizontalAlign.Start)
        Column({ space: 6 }) {
          Text(this.getQualityText())
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor(this.getQualityColorValue())
            .borderRadius(8)
          Text(this.getDominantText())
            .fontSize(11)
            .fontColor('#66726D')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Canvas(this.posterPlantContext)
        .width(SHARE_POSTER_WIDTH - 44)
        .height(SHARE_POSTER_PLANT_HEIGHT)
        .borderRadius(18)
        .backgroundColor('#F5FAF1')
        .onReady(() => {
          this.posterPlantReady = true;
          this.drawSharePosterPlant();
        })

      Row({ space: 12 }) {
        Canvas(this.posterRadarContext)
          .width(SHARE_POSTER_RADAR_WIDTH)
          .height(SHARE_POSTER_RADAR_HEIGHT)
          .onReady(() => {
            this.posterRadarReady = true;
            this.drawSharePosterRadar();
          })

        Column({ space: 6 }) {
          Text(this.getPosterRadarCommentTitle())
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getQualityColorValue())
          Text(this.getPosterRadarCommentBody())
            .fontSize(11)
            .lineHeight(16)
            .fontColor('#5F6B63')
            .maxLines(4)
        }
        .layoutWeight(1)
        .height(SHARE_POSTER_RADAR_HEIGHT)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('数据来源：WAQI · 当前仅用于免费非商业演示')
        .fontSize(9)
        .lineHeight(12)
        .fontColor('#78837B')
        .width('100%')
        .textAlign(TextAlign.Center)

      Text(`${this.sharePosterRevision}`)
        .fontSize(1)
        .fontColor('#00FFFFFF')
        .height(1)
    }
    .id(SHARE_POSTER_COMPONENT_ID)
    .width(SHARE_POSTER_WIDTH)
    .height(SHARE_POSTER_HEIGHT)
    .padding({ left: 22, right: 22, top: 22, bottom: 18 })
    .backgroundColor('#F3F7EF')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  TopInfoBar() {
    if (this.isCompactTopBar()) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Row({ space: 4 }) {
            Text('一叶知气')
              .fontSize(27)
              .lineHeight(34)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getPlantAccentColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Image($r('app.media.question'))
              .width(TOP_BAR_ICON_SIZE)
              .height(TOP_BAR_ICON_SIZE)
              .objectFit(ImageFit.Contain)
              .onClick(() => {
                this.openGuideDetail();
              })
          }
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)

          Stack() {
            if (this.shareLoading) {
              Text('...')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
            } else {
              Image($r('app.media.share'))
                .width(TOP_BAR_ICON_SIZE)
                .height(TOP_BAR_ICON_SIZE)
                .objectFit(ImageFit.Contain)
            }
          }
          .width(42)
          .height(34)
          .backgroundColor(this.getPlantAccentColor())
          .borderRadius(11)
          .border({ width: 1, color: this.getPlantAccentColor() })
          .opacity(this.canShareCurrentPoster() ? 1 : 0.45)
          .onClick(() => {
            if (this.canShareCurrentPoster()) {
              this.shareCurrentPoster();
            }
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row({ space: 8 }) {
          Text(this.loading ? '更新中' : this.getPlantMoodLabel())
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#647069')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Row({ space: 3 }) {
            Image($r('app.media.locate'))
              .width(TOP_BAR_ICON_SIZE)
              .height(TOP_BAR_ICON_SIZE)
              .objectFit(ImageFit.Contain)
              .translate({ y: -1.5 })
            Text(this.getCityName())
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#1F2925')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('50%')
          .height(34)
          .padding({ left: 8, right: 8 })
          .backgroundColor('#E7EFE4')
          .borderRadius(10)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.openCitySwitch();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height(98)
      .padding({ left: 14, right: 14, top: 10, bottom: 16 })
      .backgroundColor('#F7FAF3')
      .borderRadius(14)
      .shadow({ radius: 12, color: '#1A000000', offsetX: 0, offsetY: 4 })
    } else {
      Row({ space: 10 }) {
        Column({ space: 1 }) {
          Row({ space: 6 }) {
            Text(APP_DISPLAY_NAME)
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getPlantAccentColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Image($r('app.media.question'))
              .width(TOP_BAR_ICON_SIZE)
              .height(TOP_BAR_ICON_SIZE)
              .objectFit(ImageFit.Contain)
              .onClick(() => {
                this.openGuideDetail();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(this.loading ? '更新中' : this.getPlantMoodLabel())
            .fontSize(11)
            .fontColor('#647069')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Row({ space: 3 }) {
          Image($r('app.media.locate'))
            .width(TOP_BAR_ICON_SIZE)
            .height(TOP_BAR_ICON_SIZE)
            .objectFit(ImageFit.Contain)
            .translate({ y: -1.5 })
          Text(this.getCityName())
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1F2925')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('34%')
        .height(34)
        .padding({ left: 10, right: 10 })
        .backgroundColor('#E7EFE4')
        .borderRadius(10)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.openCitySwitch();
        })

        Stack() {
          if (this.shareLoading) {
            Text('...')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          } else {
            Image($r('app.media.share'))
              .width(TOP_BAR_ICON_SIZE)
              .height(TOP_BAR_ICON_SIZE)
              .objectFit(ImageFit.Contain)
          }
        }
        .width(42)
        .height(34)
        .backgroundColor(this.getPlantAccentColor())
        .borderRadius(11)
        .border({ width: 1, color: this.getPlantAccentColor() })
        .opacity(this.canShareCurrentPoster() ? 1 : 0.45)
        .onClick(() => {
          if (this.canShareCurrentPoster()) {
            this.shareCurrentPoster();
          }
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
  }

  @Builder
  PlantInfoOverlay() {
    Column({ space: 2 }) {
      Text('今日 AQI')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#66726D')
      Text(this.getAqiText())
        .fontSize(58)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getQualityColorValue())
        .lineHeight(62)
        .scale({ x: this.getAqiPulseScale(), y: this.getAqiPulseScale() })
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
  MockPollutantInput(label: string, pollutantKey: string) {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        Text(label)
          .fontSize(10)
          .fontColor('#5E6A63')
          .layoutWeight(1)
        Text(this.getMockEditorValue(pollutantKey))
          .width(58)
          .height(26)
          .fontSize(11)
          .fontColor('#26312B')
          .textAlign(TextAlign.Center)
          .backgroundColor('#FFFFFF')
          .borderRadius(6)
      }
      .width('100%')

      Slider({ value: this.getMockSliderValue(this.getMockEditorValue(pollutantKey)), min: 0, max: 300, step: 1 })
        .id(`${pollutantKey}-slider-${this.mockEditorRevision}`)
        .width('100%')
        .height(18)
        .selectedColor(getQualityColor(this.getMockSliderValue(this.getMockEditorValue(pollutantKey))))
        .trackColor('#FFFFFF')
        .onChange((nextValue: number) => {
          this.updateMockEditorValue(pollutantKey, this.getMockSliderText(nextValue));
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

      Row({ space: 8 }) {
        this.MockPollutantInput('PM2.5', 'pm25')
        this.MockPollutantInput('PM10', 'pm10')
      }
      .width('100%')

      Row({ space: 8 }) {
        this.MockPollutantInput('O3', 'o3')
        this.MockPollutantInput('NO2', 'no2')
      }
      .width('100%')

      Row({ space: 8 }) {
        this.MockPollutantInput('SO2', 'so2')
        this.MockPollutantInput('CO', 'co')
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
      Row({ space: 8 }) {
        Text('选择一座城市，种下空气植物')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor('#26312B')
          .textAlign(TextAlign.Center)
        Image($r('app.media.question'))
          .width(TOP_BAR_ICON_SIZE)
          .height(TOP_BAR_ICON_SIZE)
          .objectFit(ImageFit.Contain)
          .onClick(() => {
            this.openGuideDetail();
          })
      }
      .alignItems(VerticalAlign.Center)
      Text('还没有可展示的空气植物。先定位或搜索城市，之后你将获得一颗独一无二的空气植物。')
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
        .backgroundColor(this.getPlantStageBackgroundColor())
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
    .backgroundColor(this.getPlantStageBackgroundColor())
    .gesture(
      PanGesture({ direction: PanDirection.Vertical, distance: 10 })
        .onActionEnd(() => {
          this.toggleDetailLayout();
        })
    )
  }

  @Builder
  DataSheet() {
    Column({ space: 8 }) {
      this.PollutantPanel()
      this.SourcePanel()
    }
    .width('100%')
    .height(this.getDetailPanelHeight())
    .padding({ left: 18, right: 18, top: 16, bottom: 16 })
    .backgroundColor('#E8F0E2')
    .borderRadius({ topLeft: 24, topRight: 24, bottomLeft: 0, bottomRight: 0 })
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
      .height(172)

      Row({ space: 8 }) {
        Blank()
          .layoutWeight(1)
        this.AqiAgentEntry()
        Blank()
          .layoutWeight(1)
      }
      .width('100%')
      .height(46)

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
  AqiAgentEntry() {
    Row() {
      FunctionComponent({
        agentId: AQI_AGENT_ID,
        controller: this.aqiAgentController,
        options: {
          title: '问问AQI水平如何',
          queryText: this.getAqiAgentQueryText()
        },
        onError: (err: BusinessError) => {
          this.statusText = `小艺智能体暂不可用：${err.message}`;
        }
      })
        .width('100%')
        .height(44)
        .translate({ y: -1 })
    }
    .width(180)
    .height(46)
    .margin({ top: -3 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  SourcePanel() {
    Column({ space: 6 }) {
      Text(this.getSourceText())
        .fontSize(11)
        .fontColor('#66706A')
        .lineHeight(16)
        .width('100%')
    }
    .width('100%')
  }

  @Builder
  BottomSafeAreaTint() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
      }
      .width('100%')
      .height('1%')
      .backgroundColor('#E8F0E2')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
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
        .hitTestBehavior(HitTestMode.Transparent)

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
          this.BottomSafeAreaTint()
        }
        .width('100%')
        .height('100%')
        .opacity(this.detailLayoutProgress)
        .hitTestBehavior(HitTestMode.Transparent)

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
      .hitTestBehavior(HitTestMode.Transparent)

      if (this.hasCityData()) {
        Column() {
          this.AqiSharePosterSnapshot()
        }
        .position({ x: -2000, y: 0 })
        .accessibilityGroup(true)
        .accessibilityLevel('no')
      }

      if (this.showAppearancePicker && this.hasCityData()) {
        Column() {
          this.AppearancePickerOverlay()
        }
        .width('100%')
        .height('100%')
        .zIndex(5)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getPlantStageBackgroundColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .onAreaChange((oldValue, newValue) => {
      const nextWidth = Number(newValue.width);
      if (!isNaN(nextWidth) && nextWidth > 0 && Math.abs(nextWidth - this.viewportWidth) > 1) {
        this.viewportWidth = nextWidth;
      }
      const nextHeight = Number(newValue.height);
      if (!isNaN(nextHeight) && nextHeight > 0 && Math.abs(nextHeight - this.viewportHeight) > 1) {
        this.viewportHeight = nextHeight;
      }
    })
  }
}
