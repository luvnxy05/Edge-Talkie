// 关于与合规页面（隐私政策 / 用户协议 / 投诉举报）
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

@Entry
@Component
struct About {
  @State tab: number = 0;   // 0=关于 1=隐私政策 2=用户协议 3=投诉举报
  private context = getContext(this) as common.UIAbilityContext;

  build() {
    Column({ space: 0 }) {
      // 顶栏
      Row() {
        Text('‹ 返回')
          .fontSize(16)
          .fontColor('#0A59F7')
          .onClick(() => {
            router.back();
          })
        Blank()
        Text('关于与合规').fontSize(18).fontWeight(FontWeight.Bold)
        Blank()
        Text('    ').fontSize(16)   // 占位保持标题居中
      }
      .width('100%')
      .padding(16)

      // Tab 栏
      Row({ space: 0 }) {
        this.tabButton('关于', 0)
        this.tabButton('隐私政策', 1)
        this.tabButton('用户协议', 2)
        this.tabButton('投诉举报', 3)
      }
      .width('100%')

      // 内容区
      Scroll() {
        Column({ space: 12 }) {
          if (this.tab === 0) {
            this.aboutContent()
          } else if (this.tab === 1) {
            this.privacyContent()
          } else if (this.tab === 2) {
            this.agreementContent()
          } else {
            this.reportContent()
          }
        }
        .width('100%')
        .padding(20)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  @Builder
  tabButton(label: string, idx: number) {
    Text(label)
      .fontSize(14)
      .fontColor(this.tab === idx ? '#0A59F7' : '#666666')
      .fontWeight(this.tab === idx ? FontWeight.Bold : FontWeight.Normal)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .padding({ top: 10, bottom: 10 })
      .onClick(() => {
        this.tab = idx;
      })
  }

  @Builder
  aboutContent() {
    Column({ space: 12 }) {
      Text('端语').fontSize(22).fontWeight(FontWeight.Bold)
      Text('本地大模型对话 · HarmonyOS NEXT').fontSize(13).fontColor('#999999')
      this.section('版本', '0.1.0')
      this.section('推理引擎', '阿里巴巴 MNN（端侧推理）')
      this.section('模型来源', 'ModelScope MNN 官方组织（Apache-2.0）')
      this.section('开源许可', '本项目 Apache License 2.0')
      this.section('项目主页', 'https://gitee.com/MikeDev')
      Text('端语是一款纯本地推理的大模型聊天应用，所有对话内容仅在设备本地处理，不会上传至任何服务器。')
        .fontSize(13)
        .fontColor('#666666')
        .lineHeight(20)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  privacyContent() {
    Column({ space: 10 }) {
      Text('隐私政策').fontSize(18).fontWeight(FontWeight.Bold)
      Text('更新日期：2026 年 8 月').fontSize(12).fontColor('#999999')
      Text('端语是一款纯本地运行的对话应用，我们高度重视您的隐私保护。本政策说明端语如何处理您的信息。')
        .fontSize(13).lineHeight(20)
      this.bold('一、我们收集的信息')
      Text('端语不收集、不上传、不存储您的任何个人信息。所有对话内容、输入文本均在您的设备本地处理，不经过任何服务器。')
        .fontSize(13).lineHeight(20)
      this.bold('二、模型下载')
      Text('当您使用「模型管理」功能下载模型时，模型文件从 ModelScope（魔搭）平台下载至您的设备。此过程仅传输模型文件本身，不涉及您的对话内容或个人信息。')
        .fontSize(13).lineHeight(20)
      this.bold('三、本地 API 服务')
      Text('「API 服务」功能默认关闭。开启后，您的设备将在局域网内监听 8080 端口，供您授权的设备调用本地模型推理。此服务仅在本机运行，对话内容不离开您的设备。请勿在不信任的网络环境中开启。')
        .fontSize(13).lineHeight(20)
      this.bold('四、数据存储')
      Text('您的对话历史仅保存在设备本地存储中（应用沙箱内），您可以随时在应用内删除。卸载应用将清除本地数据。')
        .fontSize(13).lineHeight(20)
      this.bold('五、联系我们')
      Text('如对本政策有任何疑问，请通过「投诉举报」页面的联系方式与我们联系。')
        .fontSize(13).lineHeight(20)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  agreementContent() {
    Column({ space: 10 }) {
      Text('用户协议').fontSize(18).fontWeight(FontWeight.Bold)
      Text('更新日期：2026 年 8 月').fontSize(12).fontColor('#999999')
      this.bold('一、服务说明')
      Text('端语提供本地大语言模型对话服务。本应用生成的回复内容由人工智能模型自动生成，仅供参考，不构成任何专业建议。')
        .fontSize(13).lineHeight(20)
      this.bold('二、人工智能生成内容标识')
      Text('根据《人工智能生成合成内容标识办法》，本应用在聊天界面展示「AI 生成」标识，提示用户相关内容由人工智能生成。')
        .fontSize(13).lineHeight(20)
      this.bold('三、使用规范')
      Text('您承诺不利用本应用生成、传播违反法律法规或公序良俗的内容。因您使用本应用产生的后果由您自行承担。')
        .fontSize(13).lineHeight(20)
      this.bold('四、模型许可')
      Text('本应用内置的模型均采用 Apache-2.0 等开源许可。您应遵守相应模型的许可证条款。')
        .fontSize(13).lineHeight(20)
      this.bold('五、免责声明')
      Text('本应用按「现状」提供，不对生成内容的准确性、完整性、合法性作任何明示或暗示的保证。')
        .fontSize(13).lineHeight(20)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  reportContent() {
    Column({ space: 10 }) {
      Text('投诉举报').fontSize(18).fontWeight(FontWeight.Bold)
      Text('如您发现本应用生成的内容涉嫌违法违规，或对本应用有任何投诉、建议，请通过以下方式联系我们：')
        .fontSize(13).lineHeight(20)
      this.section('联系邮箱', 'feedback@example.com')
      this.section('响应时效', '我们将在收到反馈后 15 个工作日内处理')
      Text('请在反馈时提供具体内容、发生时间及相关证据，以便我们及时核实处理。')
        .fontSize(13).lineHeight(20).fontColor('#666666')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  section(label: string, value: string) {
    Row() {
      Text(label).fontSize(13).fontColor('#999999')
      Blank()
      Text(value).fontSize(13).fontColor('#222222')
    }
    .width('100%')
  }

  @Builder
  bold(text: string) {
    Text(text).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#222222')
  }
}
