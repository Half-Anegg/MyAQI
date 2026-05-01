import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { AqiSnapshot, PlantState, PollutantDisplayItem, StoredCityRecord, createInitialPlantState } from '../models/AqiModels';
import { AqiClient } from '../services/AqiClient';
import { LocationService } from '../services/LocationService';
import {
  buildPollutantItems,
  getPlantGrowthDays,
  getPlantMaturity,
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

@Entry
@Component
struct Index {
  private aqiClient: AqiClient = new AqiClient();
  private locationService: LocationService = new LocationService();
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
      if (this.touchPulse > 0) {
        this.touchPulse = Math.max(0, this.touchPulse - 0.035);
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
        `植物已吸收这次空气数据，成长 ${Math.min(getPlantGrowthDays(nextPlant), 7)}/7 天`;

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
    this.touchPulse = 1;
    this.statusText = '电子植物轻轻回应了一下';
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
    if (growthDays < 7) {
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
    if (growthDays >= 7) {
      return '成熟 7/7 天';
    }
    if (growthDays === 0) {
      return '等待第一天数据';
    }
    return `幼苗 ${growthDays}/7 天`;
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

  private leafColor(score: number): string {
    const r = Math.round(126 + (52 - 126) * score);
    const g = Math.round(130 + (151 - 130) * score);
    const b = Math.round(102 + (95 - 102) * score);
    return `rgb(${r},${g},${b})`;
  }

  private leafShadowColor(score: number): string {
    const r = Math.round(90 + (34 - 90) * score);
    const g = Math.round(100 + (112 - 100) * score);
    const b = Math.round(78 + (74 - 78) * score);
    return `rgb(${r},${g},${b})`;
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

    ctx.clearRect(0, 0, width, height);
    ctx.fillStyle = '#EEF4E8';
    ctx.fillRect(0, 0, width, height);
    this.drawAirParticles(ctx, width, height, plant.particleScore, time);

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
    const maturity = getPlantMaturity(plant);
    const growth = 0.22 + maturity * 0.78;
    const stress = plant.averageStress;
    const vitality = 1 - stress;
    const breathe = Math.sin(time) * (2 + growth * 3) * (0.35 + vitality * 0.65);
    const rootX = width / 2 + offsetX;
    const rootY = height - 40 - this.detailLayoutProgress * PLANT_DETAIL_SHIFT;
    const stemHeight = (82 + maturity * 238) * (0.74 + plant.heightScore * 0.26);
    const topY = rootY - stemHeight;
    const bend = (plant.droopScore - 0.24) * (32 + maturity * 18) + breathe;
    const topX = rootX + bend * (0.7 + growth * 0.3);
    const ctrlX = rootX - bend * 0.36;
    const ctrlY = rootY - stemHeight * 0.56;
    const frondCount = maturity < 0.24 ? 2 : Math.max(3, Math.round(2 + maturity * 8 + plant.leafScore * 2));
    const glowCount = maturity < 0.70 ? 0 : Math.round(plant.bloomScore * maturity * 6);
    const stemColor = this.leafShadowColor(plant.colorScore);
    const leafColor = this.leafColor(plant.colorScore);

    this.drawSoilMound(ctx, rootX, rootY, growth, vitality);

    ctx.strokeStyle = stemColor;
    ctx.lineWidth = 4.8 + growth * 3.8;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(rootX, rootY);
    ctx.quadraticCurveTo(ctrlX, ctrlY, topX, topY);
    ctx.stroke();

    for (let i = 0; i < frondCount; i++) {
      const progress = maturity < 0.24 ? 0.38 + i * 0.22 : 0.18 + (i + 1) / (frondCount + 1) * 0.70;
      const inverse = 1 - progress;
      const side = i % 2 === 0 ? -1 : 1;
      const anchorX = inverse * inverse * rootX + 2 * inverse * progress * ctrlX + progress * progress * topX;
      const anchorY = inverse * inverse * rootY + 2 * inverse * progress * ctrlY + progress * progress * topY;
      const sway = Math.sin(time + i * 0.72) * (2 + maturity * 5) * vitality;
      const length = (42 + maturity * 104 + plant.leafScore * 24) * (0.70 + progress * 0.42);
      const endX = anchorX + side * (length * (0.64 + maturity * 0.10) + sway);
      const endY = anchorY - length * (0.20 + progress * 0.16) + plant.droopScore * 22;
      const curve = side * (10 + maturity * 18 - plant.droopScore * 6);
      const leafletCount = maturity < 0.24 ? 1 : Math.max(3, Math.round(2 + maturity * 8 + progress * 4));
      this.drawFernFrondWorld(
        ctx,
        anchorX,
        anchorY,
        endX,
        endY,
        curve,
        leafletCount,
        leafColor,
        stemColor,
        maturity,
        progress
      );
    }

    this.drawFiddlehead(ctx, topX, topY, 14 + (1 - maturity) * 19, leafColor, stemColor);
    this.drawPulseRing(ctx, topX, topY, growth, pulse);

    for (let i = 0; i < glowCount; i++) {
      const angle = Math.PI * 2 / glowCount * i;
      const radius = 8 + maturity * 22 + pulse * 10;
      const x = topX + Math.cos(angle) * radius;
      const y = topY + Math.sin(angle) * radius * 0.72;
      ctx.globalAlpha = 0.20 + maturity * 0.20;
      ctx.fillStyle = '#E5B67F';
      ctx.beginPath();
      ctx.arc(x, y, 2 + plant.bloomScore * 2.5, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;

    this.drawSoilLip(ctx, rootX, rootY, growth);
  }

  private drawSoilMound(
    ctx: CanvasRenderingContext2D,
    rootX: number,
    rootY: number,
    growth: number,
    vitality: number
  ): void {
    ctx.globalAlpha = 0.18 + vitality * 0.12;
    ctx.fillStyle = '#8FC8A8';
    ctx.beginPath();
    ctx.ellipse(rootX, rootY + 10, 52 + growth * 54, 18 + growth * 10, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;
  }

  private drawSoilLip(ctx: CanvasRenderingContext2D, rootX: number, rootY: number, growth: number): void {
    ctx.fillStyle = '#A26F52';
    ctx.beginPath();
    ctx.moveTo(rootX - 52 - growth * 20, rootY + 14);
    ctx.lineTo(rootX + 52 + growth * 20, rootY + 14);
    ctx.lineTo(rootX + 40 + growth * 14, rootY + 62);
    ctx.lineTo(rootX - 40 - growth * 14, rootY + 62);
    ctx.closePath();
    ctx.fill();

    ctx.fillStyle = '#7C5543';
    ctx.beginPath();
    ctx.ellipse(rootX, rootY + 14, 60 + growth * 22, 14, 0, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = '#4D3E35';
    ctx.beginPath();
    ctx.ellipse(rootX, rootY + 9, 48 + growth * 18, 8, 0, 0, Math.PI * 2);
    ctx.fill();
  }

  private quadraticPoint(start: number, control: number, end: number, progress: number): number {
    const inverse = 1 - progress;
    return inverse * inverse * start + 2 * inverse * progress * control + progress * progress * end;
  }

  private quadraticTangent(start: number, control: number, end: number, progress: number): number {
    return 2 * (1 - progress) * (control - start) + 2 * progress * (end - control);
  }

  private drawFernFrondWorld(
    ctx: CanvasRenderingContext2D,
    startX: number,
    startY: number,
    endX: number,
    endY: number,
    curve: number,
    leafletCount: number,
    leafColor: string,
    stemColor: string,
    maturity: number,
    frondProgress: number
  ): void {
    const midX = (startX + endX) * 0.5;
    const midY = (startY + endY) * 0.5 - Math.abs(curve) * 0.20;
    const dx = endX - startX;
    const dy = endY - startY;
    const distance = Math.max(1, Math.sqrt(dx * dx + dy * dy));
    const normalX = -dy / distance;
    const normalY = dx / distance;
    const controlX = midX + normalX * curve;
    const controlY = midY + normalY * curve;

    ctx.strokeStyle = stemColor;
    ctx.lineWidth = 2 + maturity * 1.5;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(startX, startY);
    ctx.quadraticCurveTo(controlX, controlY, endX, endY);
    ctx.stroke();

    for (let i = 0; i < leafletCount; i++) {
      const progress = (i + 1) / (leafletCount + 1);
      const rootX = this.quadraticPoint(startX, controlX, endX, progress);
      const rootY = this.quadraticPoint(startY, controlY, endY, progress);
      const tangentX = this.quadraticTangent(startX, controlX, endX, progress);
      const tangentY = this.quadraticTangent(startY, controlY, endY, progress);
      const tangentLength = Math.max(1, Math.sqrt(tangentX * tangentX + tangentY * tangentY));
      const unitNormalX = -tangentY / tangentLength;
      const unitNormalY = tangentX / tangentLength;
      const leafLength = (7 + maturity * 9 + (1 - progress) * 4) * (0.80 + frondProgress * 0.25);
      const leafWidth = 3 + maturity * 3;
      this.drawLeafletWorld(ctx, rootX, rootY, unitNormalX, unitNormalY, leafLength, leafWidth, leafColor);
      this.drawLeafletWorld(ctx, rootX, rootY, -unitNormalX, -unitNormalY, leafLength * 0.88, leafWidth, leafColor);
    }

    ctx.fillStyle = leafColor;
    ctx.beginPath();
    ctx.arc(endX, endY, 2.6 + maturity * 1.4, 0, Math.PI * 2);
    ctx.fill();
  }

  private drawLeafletWorld(
    ctx: CanvasRenderingContext2D,
    rootX: number,
    rootY: number,
    dirX: number,
    dirY: number,
    length: number,
    leafWidth: number,
    color: string
  ): void {
    const directionLength = Math.max(1, Math.sqrt(dirX * dirX + dirY * dirY));
    const ux = dirX / directionLength;
    const uy = dirY / directionLength;
    const px = -uy;
    const py = ux;
    const tipX = rootX + ux * length;
    const tipY = rootY + uy * length;
    const midX = rootX + ux * length * 0.52;
    const midY = rootY + uy * length * 0.52;

    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.moveTo(rootX, rootY);
    ctx.quadraticCurveTo(midX + px * leafWidth, midY + py * leafWidth, tipX, tipY);
    ctx.quadraticCurveTo(midX - px * leafWidth, midY - py * leafWidth, rootX, rootY);
    ctx.fill();
  }

  private drawFiddlehead(
    ctx: CanvasRenderingContext2D,
    x: number,
    y: number,
    radius: number,
    leafColor: string,
    stemColor: string
  ): void {
    ctx.strokeStyle = stemColor;
    ctx.lineWidth = 3.4;
    ctx.lineCap = 'round';
    ctx.beginPath();
    for (let i = 0; i <= 30; i++) {
      const progress = i / 30;
      const theta = progress * Math.PI * 3.2;
      const r = radius * (1 - progress * 0.78);
      const px = x + Math.cos(theta) * r;
      const py = y + Math.sin(theta) * r;
      if (i === 0) {
        ctx.moveTo(px, py);
      } else {
        ctx.lineTo(px, py);
      }
    }
    ctx.stroke();

    ctx.globalAlpha = 0.28;
    ctx.fillStyle = leafColor;
    ctx.beginPath();
    ctx.arc(x, y, radius * 0.42, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;
  }

  private drawPulseRing(ctx: CanvasRenderingContext2D, x: number, y: number, growth: number, pulse: number): void {
    if (pulse <= 0) {
      return;
    }
    ctx.globalAlpha = pulse * 0.34;
    ctx.strokeStyle = '#E5B67F';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(x, y, 18 + growth * 18 + (1 - pulse) * 34, 0, Math.PI * 2);
    ctx.stroke();
    ctx.globalAlpha = 1;
  }

  private drawAirParticles(ctx: CanvasRenderingContext2D, width: number, height: number, stress: number, time: number): void {
    const count = Math.round(8 + stress * 30);
    ctx.fillStyle = '#6C716C';
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
    Row({ space: 8 }) {
      Text('⌖')
        .fontSize(18)
        .fontColor('#2E6D5E')
      Text(this.getCityName())
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1F2925')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .height(48)
    .padding({ left: 14, right: 14 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor('#F7FAF3')
    .borderRadius(14)
    .shadow({ radius: 12, color: '#1A000000', offsetX: 0, offsetY: 4 })
    .onClick(() => {
      this.openCitySwitch();
    })
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
    Column({ space: 18 }) {
      this.PollutantPanel()
      this.SourcePanel()
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 22, bottom: 34 })
    .backgroundColor('#E8F0E2')
    .borderRadius(24)
    .height(DETAIL_PANEL_HEIGHT)
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
        this.DataSheet()
      }
      .width('100%')
      .position({ x: 0, y: '100%' })
      .translate({ y: -this.detailLayoutProgress * DETAIL_PANEL_HEIGHT })
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#EEF4E8')
  }
}
