if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface Index_Params {
    statusText?: string;
    modelName?: string;
    aiLabelVisible?: boolean;
}
import hilog from "@ohos:hilog";
const TAG: string = 'MnnChat';
class Index extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__statusText = new ObservedPropertySimplePU('引擎未加载', this, "statusText");
        this.__modelName = new ObservedPropertySimplePU('未选择模型', this, "modelName");
        this.__aiLabelVisible = new ObservedPropertySimplePU(true, this, "aiLabelVisible");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: Index_Params) {
        if (params.statusText !== undefined) {
            this.statusText = params.statusText;
        }
        if (params.modelName !== undefined) {
            this.modelName = params.modelName;
        }
        if (params.aiLabelVisible !== undefined) {
            this.aiLabelVisible = params.aiLabelVisible;
        }
    }
    updateStateVars(params: Index_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__statusText.purgeDependencyOnElmtId(rmElmtId);
        this.__modelName.purgeDependencyOnElmtId(rmElmtId);
        this.__aiLabelVisible.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__statusText.aboutToBeDeleted();
        this.__modelName.aboutToBeDeleted();
        this.__aiLabelVisible.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __statusText: ObservedPropertySimplePU<string>;
    get statusText() {
        return this.__statusText.get();
    }
    set statusText(newValue: string) {
        this.__statusText.set(newValue);
    }
    private __modelName: ObservedPropertySimplePU<string>;
    get modelName() {
        return this.__modelName.get();
    }
    set modelName(newValue: string) {
        this.__modelName.set(newValue);
    }
    private __aiLabelVisible: ObservedPropertySimplePU<boolean>;
    get aiLabelVisible() {
        return this.__aiLabelVisible.get();
    }
    set aiLabelVisible(newValue: boolean) {
        this.__aiLabelVisible.set(newValue);
    }
    aboutToAppear(): void {
        // TODO(M1): 调用 NAPI 初始化 libMNN/libllm
        hilog.info(0x0000, TAG, 'MNN-Harmony Chat launched');
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.width('100%');
            Column.height('100%');
            Column.backgroundColor(Color.White);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // 顶栏
            Row.create();
            // 顶栏
            Row.width('100%');
            // 顶栏
            Row.padding(16);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('MNN 本地对话');
            Text.fontSize(20);
            Text.fontWeight(FontWeight.Bold);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('AI 生成');
            Text.fontSize(10);
            Text.fontColor(Color.White);
            Text.backgroundColor('#666666');
            Text.borderRadius(4);
            Text.padding({ left: 6, right: 6, top: 2, bottom: 2 });
        }, Text);
        Text.pop();
        // 顶栏
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // 状态区
            Column.create({ space: 8 });
            // 状态区
            Column.width('100%');
            // 状态区
            Column.alignItems(HorizontalAlign.Start);
            // 状态区
            Column.padding({ left: 16, right: 16 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.statusText);
            Text.fontSize(14);
            Text.fontColor('#888888');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('模型：' + this.modelName);
            Text.fontSize(12);
            Text.fontColor('#aaaaaa');
        }, Text);
        Text.pop();
        // 状态区
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // 占位聊天区
            Column.create();
            // 占位聊天区
            Column.layoutWeight(1);
            // 占位聊天区
            Column.width('100%');
            // 占位聊天区
            Column.justifyContent(FlexAlign.Center);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('聊天功能将在 M2 接入');
            Text.fontSize(16);
            Text.fontColor('#bbbbbb');
        }, Text);
        Text.pop();
        // 占位聊天区
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // 输入区占位
            Row.create({ space: 8 });
            // 输入区占位
            Row.width('100%');
            // 输入区占位
            Row.padding(16);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({ placeholder: '输入消息…' });
            TextInput.layoutWeight(1);
            TextInput.enabled(false);
        }, TextInput);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('发送');
            Button.enabled(false);
        }, Button);
        Button.pop();
        // 输入区占位
        Row.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "Index";
    }
}
registerNamedRoute(() => new Index(undefined, {}), "", { bundleName: "io.mnnkeep.harmony", moduleName: "entry", pagePath: "pages/Index", pageFullPath: "entry/src/main/ets/pages/Index", integratedHsp: "false", moduleType: "followWithHap" });
