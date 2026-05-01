import { common } from '@kit.AbilityKit';
import { AqiSnapshot, PlantState, PollutantDisplayItem, createInitialPlantState } from '../models/AqiModels';
import { AqiClient } from '../services/AqiClient';
import { LocationService } from '../services/LocationService';
import {
  buildPollutantItems,
  getPlantGrowthDays,
  getPlantMaturity,
  getQualityColor,
  updatePlantWithSnapshot
} from '../services/PlantAlgorithm';
import { PlantStore } from '../storage/PlantStore';

const PREVIEW_CITY_KEY: string = 'preview';
const PREVIEW_CITY_NAME: string = '空气花园';
const DEFAULT_CANVAS_WIDTH: number = 320;
const CANVAS_HEIGHT: number = 340;

@Entry
@Component
struct Index {
  private aqiClient: AqiClient = new AqiClient();
  private locationService: LocationService = new LocationService();
  private plantStore: PlantStore = new PlantStore();
  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);

  @State cityInput: string = '北京';
  @State loading: boolean = false;
  @State statusText: string = '正在准备空气花园';
  @State currentSnapshot: AqiSnapshot | null = null;
  @State currentPlant: PlantState = createInitialPlantState(PREVIEW_CITY_KEY, PREVIEW_CITY_NAME);
  @State canvasWidth: number = DEFAULT_CANVAS_WIDTH;
  @State pollutantItems: PollutantDisplayItem[] =
    buildPollutantItems(null, createInitialPlantState(PREVIEW_CITY_KEY, PREVIEW_CITY_NAME).pollutantMemory);

  aboutToAppear(): void {
    this.prepareApp();
  }

  private async prepareApp(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    await this.plantStore.init(context);
    const lastCityKey = await this.plantStore.getLastCityKey();
    if (lastCityKey.length > 0) {
      const lastRecord = await this.plantStore.getCityRecord(lastCityKey);
      if (lastRecord !== null) {
        this.currentSnapshot = lastRecord.snapshot;
        this.currentPlant = lastRecord.plant;
        this.cityInput = lastRecord.cityName;
        this.pollutantItems = buildPollutantItems(lastRecord.snapshot?.pollutants ?? null, lastRecord.plant.pollutantMemory);
        this.statusText = '已载入上次查看的城市，刷新可获取最新空气数据';
        this.requestRedraw();
        return;
      }
    }

    if (!this.aqiClient.hasToken()) {
      this.statusText = '请先在 ApiConfig.ets 中配置 WAQI token';
      this.requestRedraw();
      return;
    }
    await this.refreshByLocation();
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

      this.currentSnapshot = snapshot;
      this.currentPlant = nextPlant;
      this.cityInput = snapshot.cityName;
      this.pollutantItems = buildPollutantItems(snapshot.pollutants, nextPlant.pollutantMemory);
      this.statusText = repeatedObservation ? '已是该监测点的最新数据，植物状态未重复累计' :
        `植物已吸收这次空气数据，成长 ${Math.min(getPlantGrowthDays(nextPlant), 7)}/7 天`;

      await this.plantStore.saveCityRecord({
        cityKey: snapshot.cityKey,
        cityName: snapshot.cityName,
        snapshot,
        plant: nextPlant
      });
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

  private getCityName(): string {
    if (this.currentSnapshot !== null) {
      return this.currentSnapshot.cityName;
    }
    return '未选择城市';
  }

  private getAqiText(): string {
    if (this.currentSnapshot === null || this.currentSnapshot.aqi === null) {
      return '--';
    }
    return Math.round(this.currentSnapshot.aqi).toString();
  }

  private getQualityText(): string {
    if (this.currentSnapshot === null) {
      return '等待数据';
    }
    return this.currentSnapshot.qualityLabel;
  }

  private getObservedText(): string {
    if (this.currentSnapshot === null || this.currentSnapshot.observedAt.length === 0) {
      return '暂无更新时间';
    }
    return `更新于 ${this.currentSnapshot.observedAt}`;
  }

  private getDominantText(): string {
    if (this.currentSnapshot === null || this.currentSnapshot.dominantPollutant.length === 0) {
      return '主要污染物 暂无';
    }
    return `主要污染物 ${this.currentSnapshot.dominantPollutant.toUpperCase()}`;
  }

  private getMissingText(): string {
    if (this.currentSnapshot === null || this.currentSnapshot.missingPollutants.length === 0) {
      return '';
    }
    return `缺失 ${this.currentSnapshot.missingPollutants.join('、')}，对应植物参数沿用上一状态`;
  }

  private getSourceText(): string {
    if (this.currentSnapshot === null) {
      return '数据来源：WAQI，当前仅用于免费非商业演示。';
    }
    return `数据来源：${this.currentSnapshot.sourceName}，当前仅用于免费非商业演示。`;
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

  private getGrowthText(): string {
    const growthDays = getPlantGrowthDays(this.currentPlant);
    if (growthDays >= 7) {
      return '成熟 7/7 天';
    }
    if (growthDays === 0) {
      return '等待第一天数据';
    }
    return `幼苗 ${growthDays}/7 天`;
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
    const ctx = this.canvasContext;
    const plant = this.currentPlant;
    const width = this.canvasWidth;
    const height = CANVAS_HEIGHT;
    const maturity = getPlantMaturity(plant);
    const growth = 0.16 + maturity * 0.84;
    const stress = plant.averageStress;
    const vitality = 1 - stress;
    const rootX = width / 2;
    const rootY = height - 62;
    const stemHeight = (58 + maturity * 142) * (0.72 + plant.heightScore * 0.28);
    const topY = rootY - stemHeight;
    const bend = (plant.droopScore - 0.24) * 44;
    const topX = rootX + bend * (0.7 + growth * 0.3);
    const ctrlX = rootX - bend * 0.36;
    const ctrlY = rootY - stemHeight * 0.56;
    const frondCount = Math.max(2, Math.round(2 + maturity * 7 + plant.leafScore * 2));
    const glowCount = Math.max(1, Math.round(plant.bloomScore * (1 + maturity * 5)));
    const stemColor = this.leafShadowColor(plant.colorScore);
    const leafColor = this.leafColor(plant.colorScore);

    ctx.clearRect(0, 0, width, height);
    ctx.fillStyle = '#EEF4E8';
    ctx.fillRect(0, 0, width, height);
    this.drawAirParticles(ctx, width, height, plant.particleScore);
    this.drawSoilMound(ctx, rootX, rootY, growth, vitality);

    ctx.strokeStyle = stemColor;
    ctx.lineWidth = 4 + growth * 3;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(rootX, rootY);
    ctx.quadraticCurveTo(ctrlX, ctrlY, topX, topY);
    ctx.stroke();

    for (let i = 0; i < frondCount; i++) {
      const progress = 0.20 + (i + 1) / (frondCount + 1) * 0.68;
      const inverse = 1 - progress;
      const side = i % 2 === 0 ? -1 : 1;
      const anchorX = inverse * inverse * rootX + 2 * inverse * progress * ctrlX + progress * progress * topX;
      const anchorY = inverse * inverse * rootY + 2 * inverse * progress * ctrlY + progress * progress * topY;
      const length = (34 + maturity * 66 + plant.leafScore * 18) * (0.74 + progress * 0.46);
      const angleBase = 0.56 + progress * 0.28;
      const angle = side > 0 ? -angleBase + plant.droopScore * 0.44 : Math.PI + angleBase - plant.droopScore * 0.44;
      const leafletCount = Math.max(2, Math.round(2 + maturity * 7 + progress * 4));
      const curve = (1 - maturity) * 11 + plant.droopScore * 10;
      this.drawFernFrond(ctx, anchorX, anchorY, length, angle, leafletCount, curve, leafColor, stemColor, maturity);
    }

    this.drawFiddlehead(ctx, topX, topY, 12 + (1 - maturity) * 15, leafColor, stemColor);

    for (let i = 0; i < glowCount; i++) {
      const angle = Math.PI * 2 / glowCount * i;
      const radius = 8 + maturity * 18;
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
    ctx.ellipse(rootX, rootY + 10, 44 + growth * 44, 16 + growth * 8, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;
  }

  private drawSoilLip(ctx: CanvasRenderingContext2D, rootX: number, rootY: number, growth: number): void {
    ctx.fillStyle = '#A26F52';
    ctx.beginPath();
    ctx.moveTo(rootX - 44 - growth * 16, rootY + 14);
    ctx.lineTo(rootX + 44 + growth * 16, rootY + 14);
    ctx.lineTo(rootX + 34 + growth * 12, rootY + 56);
    ctx.lineTo(rootX - 34 - growth * 12, rootY + 56);
    ctx.closePath();
    ctx.fill();

    ctx.fillStyle = '#7C5543';
    ctx.beginPath();
    ctx.ellipse(rootX, rootY + 14, 52 + growth * 18, 13, 0, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = '#4D3E35';
    ctx.beginPath();
    ctx.ellipse(rootX, rootY + 9, 40 + growth * 16, 8, 0, 0, Math.PI * 2);
    ctx.fill();
  }

  private drawFernFrond(
    ctx: CanvasRenderingContext2D,
    x: number,
    y: number,
    length: number,
    angle: number,
    leafletCount: number,
    curve: number,
    leafColor: string,
    stemColor: string,
    maturity: number
  ): void {
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(angle);
    ctx.strokeStyle = stemColor;
    ctx.lineWidth = 2 + maturity * 1.5;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.quadraticCurveTo(length * 0.48, -curve, length, -curve * 0.18);
    ctx.stroke();

    for (let i = 0; i < leafletCount; i++) {
      const progress = (i + 1) / (leafletCount + 1);
      const leafX = length * progress;
      const leafY = -Math.sin(progress * Math.PI) * curve;
      const leafLength = (7 + maturity * 8 + (1 - progress) * 4) * (0.86 + progress * 0.22);
      const leafWidth = 3.2 + maturity * 2.8;
      this.drawLeaflet(ctx, leafX, leafY, leafLength, leafWidth, -0.94, leafColor);
      this.drawLeaflet(ctx, leafX, leafY, leafLength * 0.92, leafWidth, 0.94, leafColor);
    }

    ctx.fillStyle = leafColor;
    ctx.beginPath();
    ctx.arc(length, -curve * 0.18, 2.6 + maturity * 1.4, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  private drawLeaflet(
    ctx: CanvasRenderingContext2D,
    x: number,
    y: number,
    length: number,
    leafWidth: number,
    angle: number,
    color: string
  ): void {
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(angle);
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.quadraticCurveTo(length * 0.48, -leafWidth, length, 0);
    ctx.quadraticCurveTo(length * 0.48, leafWidth, 0, 0);
    ctx.fill();
    ctx.restore();
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

  private drawAirParticles(ctx: CanvasRenderingContext2D, width: number, height: number, stress: number): void {
    const count = Math.round(8 + stress * 30);
    ctx.fillStyle = '#6C716C';
    for (let i = 0; i < count; i++) {
      const x = 20 + (i * 57) % (width - 40);
      const y = 24 + (i * 83) % (height - 140);
      const radius = 1 + stress * 2.2;
      ctx.globalAlpha = 0.08 + stress * 0.18;
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
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
          this.drawPlant();
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
        }, (item: PollutantDisplayItem) => item.key)
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
    Scroll() {
      Column({ space: 16 }) {
        this.Header()
        this.SearchPanel()
        this.PlantPanel()
        this.PollutantPanel()
        this.SourcePanel()
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 24, bottom: 32 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F4F6F1')
  }
}
