import { router } from '@kit.ArkUI';
import { GUIDE_SECTIONS, GuideSection } from '../content/GuideContent';

@Entry
@Component
struct GuideDetail {
  private goBack(): void {
    router.back();
  }

  @Builder
  SectionCard(section: GuideSection) {
    Column({ space: 10 }) {
      Text(section.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#22302A')
        .width('100%')

      ForEach(section.paragraphs, (paragraph: string) => {
        Text(paragraph)
          .fontSize(14)
          .lineHeight(22)
          .fontColor('#52615A')
          .width('100%')
      }, (paragraph: string) => `${section.title}-${paragraph}`)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor('#FAFCF7')
    .borderRadius(16)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column({ space: 0 }) {
        Row({ space: 10 }) {
          Button('返回')
            .height(36)
            .fontSize(14)
            .backgroundColor('#EEF3EA')
            .fontColor('#2F3A34')
            .borderRadius(8)
            .onClick(() => {
              this.goBack();
            })

          Column({ space: 2 }) {
            Text('一叶知气·空气花园')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#22302A')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('AQI 与空气植物说明')
              .fontSize(12)
              .fontColor('#6A756E')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .height(64)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .backgroundColor('#F7FAF3')

        Scroll() {
          Column({ space: 14 }) {
            Text('选择城市后，本应用会为您呈现您的城市此时的AQI值，并种下一棵空气植物。')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .lineHeight(20)
              .fontColor('#66736B')
              .width('100%')
              .padding({ left: 4, right: 4 })

            ForEach(GUIDE_SECTIONS, (section: GuideSection) => {
              this.SectionCard(section)
            }, (section: GuideSection) => section.title)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 28 })
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#EEF4E8')
  }
}
