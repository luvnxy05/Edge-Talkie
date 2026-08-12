// MNN-Harmony Chat 首页（M0 壳：后续接入 NAPI 推理层）
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'MnnChat';

@Entry
@Component
struct Index {
  @State statusText: string = '引擎未加载';
  @State modelName: string = '未选择模型';
  @State aiLabelVisible: boolean = true;

  aboutToAppear(): void {
    // TODO(M1): 调用 NAPI 初始化 libMNN/libllm
    hilog.info(0x0000, TAG, 'MNN-Harmony Chat launched');
  }

  build() {
    Column({ space: 12 }) {
      // 顶栏
      Row() {
        Text('MNN 本地对话')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
        Blank()
        Text('AI 生成')
          .fontSize(10)
          .fontColor(Color.White)
          .backgroundColor('#666666')
          .borderRadius(4)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      }
      .width('100%')
      .padding(16)

      // 状态区
      Column({ space: 8 }) {
        Text(this.statusText).fontSize(14).fontColor('#888888')
        Text('模型：' + this.modelName).fontSize(12).fontColor('#aaaaaa')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16 })

      // 占位聊天区
      Column() {
        Text('聊天功能将在 M2 接入')
          .fontSize(16)
          .fontColor('#bbbbbb')
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)

      // 输入区占位
      Row({ space: 8 }) {
        TextInput({ placeholder: '输入消息…' })
          .layoutWeight(1)
          .enabled(false)
        Button('发送')
          .enabled(false)
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }
}
