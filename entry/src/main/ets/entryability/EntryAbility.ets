import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'MnnChat';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'Ability onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', async (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0000, TAG, 'Content loaded');
      try {
        const mainWindow = windowStage.getMainWindowSync();
        // 关闭全屏沉浸布局，内容避让状态栏
        await mainWindow.setWindowLayoutFullScreen(false);
        hilog.info(0x0000, TAG, 'Window layout full screen disabled');
      } catch (e) {
        hilog.warn(0x0000, TAG, 'window config failed: %{public}s', JSON.stringify(e));
      }
    });
  }
}
