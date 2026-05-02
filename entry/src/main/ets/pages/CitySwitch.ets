import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { AqiSnapshot, StoredCityRecord } from '../models/AqiModels';
import { AqiClient } from '../services/AqiClient';
import { LocationService } from '../services/LocationService';
import { MockAqiService } from '../services/MockAqiService';
import { getPlantGrowthDays, normalizePlantState, PLANT_MATURITY_DAYS, updatePlantWithSnapshot } from '../services/PlantAlgorithm';
import { PlantStore } from '../storage/PlantStore';

@Entry
@Component
struct CitySwitch {
  private aqiClient: AqiClient = new AqiClient();
  private locationService: LocationService = new LocationService();
  private mockAqiService: MockAqiService = new MockAqiService();
  private plantStore: PlantStore = new PlantStore();

  @State cityInput: string = '';
  @State loading: boolean = false;
  @State statusText: string = '选择一座城市，进入它的空气植物。';
  @State cityRecords: StoredCityRecord[] = [];
  @State lastCityKey: string = '';

  aboutToAppear(): void {
    this.preparePage();
  }

  private async preparePage(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await this.plantStore.init(context);
      this.lastCityKey = await this.plantStore.getLastCityKey();
      await this.reloadRecords();
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    }
  }

  private async reloadRecords(): Promise<void> {
    this.cityRecords = await this.plantStore.getAllCityRecords();
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
    }, `正在查询 ${city}`);
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
      this.lastCityKey = snapshot.cityKey;
      await this.reloadRecords();
      this.statusText = `已创建 ${snapshot.cityName}`;
      this.goBack();
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  private async locateCity(): Promise<void> {
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
      const nextPlant = updatePlantWithSnapshot(storedPlant, snapshot);
      await this.plantStore.saveCityRecord({
        cityKey: snapshot.cityKey,
        cityName: snapshot.cityName,
        snapshot,
        plant: nextPlant,
        lastFetchedAt: new Date().toISOString()
      });
      this.lastCityKey = snapshot.cityKey;
      await this.reloadRecords();
      this.statusText = `已切换到 ${snapshot.cityName}`;
      this.goBack();
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  private async selectRecord(record: StoredCityRecord): Promise<void> {
    if (this.loading) {
      return;
    }
    try {
      await this.plantStore.saveLastCityKey(record.cityKey);
      this.lastCityKey = record.cityKey;
      this.statusText = `已切换到 ${record.cityName}`;
      this.goBack();
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    }
  }

  private confirmDeleteRecord(record: StoredCityRecord): void {
    AlertDialog.show({
      title: '删除历史城市',
      message: `确定删除 ${record.cityName} 吗？这个城市的植物生长数据将被删除，且无法恢复。`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#B94F5F',
        action: () => {
          this.deleteRecord(record);
        }
      }
    });
  }

  private async deleteRecord(record: StoredCityRecord): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    try {
      await this.plantStore.deleteCityRecord(record.cityKey);
      this.lastCityKey = await this.plantStore.getLastCityKey();
      await this.reloadRecords();
      this.statusText = `已删除 ${record.cityName} 的植物数据`;
    } catch (error) {
      this.statusText = this.getErrorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  private goBack(): void {
    try {
      router.back();
    } catch (error) {
    }
  }

  private getErrorMessage(error: Error | Object): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return '暂时无法切换城市';
  }

  private getRecordAqiText(record: StoredCityRecord): string {
    if (record.snapshot === null || record.snapshot.aqi === null) {
      return '--';
    }
    return Math.round(record.snapshot.aqi).toString();
  }

  private getRecordSubText(record: StoredCityRecord): string {
    const plant = normalizePlantState(record.plant);
    const growthDays = getPlantGrowthDays(plant);
    const quality = record.snapshot === null ? '暂无 AQI' : record.snapshot.qualityLabel;
    if (growthDays >= PLANT_MATURITY_DAYS) {
      return `${quality} · 成长 ${growthDays} 天`;
    }
    return `${quality} · 成长 ${growthDays}/${PLANT_MATURITY_DAYS} 天`;
  }

  @Builder
  CityRecordList() {
    Column({ space: 10 }) {
      ForEach(this.cityRecords, (record: StoredCityRecord) => {
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text(record.cityName)
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor('#22302A')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.getRecordSubText(record))
              .fontSize(12)
              .fontColor('#66736B')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text(this.getRecordAqiText(record))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(record.cityKey === this.lastCityKey ? '#2E6D5E' : '#59645E')

          Button(record.cityKey === this.lastCityKey ? '当前' : '进入')
            .height(30)
            .fontSize(12)
            .enabled(!this.loading)
            .backgroundColor(record.cityKey === this.lastCityKey ? '#2E6D5E' : '#6C7B72')
            .borderRadius(8)
            .onClick(() => {
              this.selectRecord(record);
            })

          Button('删除')
            .height(30)
            .fontSize(12)
            .enabled(!this.loading)
            .fontColor('#B94F5F')
            .backgroundColor('#F4E5E3')
            .borderRadius(8)
            .onClick(() => {
              this.confirmDeleteRecord(record);
            })
        }
        .width('100%')
        .padding(14)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
      }, (record: StoredCityRecord) => record.cityKey)
    }
    .width('100%')
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        Row() {
          Button('返回')
            .height(36)
            .fontSize(14)
            .backgroundColor('#EEF3EA')
            .fontColor('#2F3A34')
            .borderRadius(8)
            .onClick(() => {
              this.goBack();
            })
          Blank()
        }
        .width('100%')

        Column({ space: 8 }) {
          Text('切换城市')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor('#202A25')
            .width('100%')
          Text('每座城市只保留一株植物，定位会优先使用“某某市”。')
            .fontSize(13)
            .fontColor('#65716A')
            .lineHeight(20)
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column({ space: 10 }) {
          TextInput({ placeholder: '输入城市，如 北京 / 上海 / 成都', text: this.cityInput })
            .height(44)
            .fontSize(15)
            .backgroundColor('#FFFFFF')
            .borderRadius(10)
            .onChange((value: string) => {
              this.cityInput = value;
            })

          Row({ space: 10 }) {
            Button('搜索城市')
              .height(42)
              .fontSize(15)
              .enabled(!this.loading)
              .backgroundColor('#2E6D5E')
              .borderRadius(10)
              .layoutWeight(1)
              .onClick(() => {
                this.searchCity();
              })
            Button('定位城市')
              .height(42)
              .fontSize(15)
              .enabled(!this.loading)
              .backgroundColor('#4E7D82')
              .borderRadius(10)
              .layoutWeight(1)
              .onClick(() => {
                this.locateCity();
              })
          }
          .width('100%')

          Text(this.statusText)
            .fontSize(12)
            .fontColor('#65716A')
            .lineHeight(18)
            .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#E8F0E2')
        .borderRadius(16)

        Column({ space: 12 }) {
          Text('已查看城市')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#26312B')
            .width('100%')
          if (this.cityRecords.length === 0) {
            Text('暂无城市记录，可以先定位或搜索。')
              .fontSize(13)
              .fontColor('#6A756E')
              .width('100%')
              .padding(14)
              .backgroundColor('#FFFFFF')
              .borderRadius(12)
          } else {
            this.CityRecordList()
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 18, bottom: 30 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F4F7EF')
  }
}
