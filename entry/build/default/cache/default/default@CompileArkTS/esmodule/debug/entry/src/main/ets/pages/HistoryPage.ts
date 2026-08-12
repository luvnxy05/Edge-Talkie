if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface HistoryPage_Params {
    records?: HistoryRecord[];
}
import type common from "@ohos:app.ability.common";
import preferences from "@ohos:data.preferences";
import type { HistoryRecord } from '../model/HealthData';
const HISTORY_KEY: string = 'history_records';
class HistoryPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__records = new ObservedPropertyObjectPU([], this, "records");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: HistoryPage_Params) {
        if (params.records !== undefined) {
            this.records = params.records;
        }
    }
    updateStateVars(params: HistoryPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__records.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__records.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __records: ObservedPropertyObjectPU<HistoryRecord[]>;
    get records() {
        return this.__records.get();
    }
    set records(newValue: HistoryRecord[]) {
        this.__records.set(newValue);
    }
    aboutToAppear(): void {
        this.loadRecords();
    }
    loadRecords(): void {
        const context = getContext(this) as common.UIAbilityContext;
        const pref = preferences.getPreferencesSync(context, { name: 'health_store' });
        try {
            const raw: string = pref.getSync(HISTORY_KEY, '[]') as string;
            this.records = JSON.parse(raw) as HistoryRecord[];
        }
        catch (err) {
            this.records = [];
        }
        // 倒序：最新在前
        this.records = this.records.reverse();
    }
    clearAll(): void {
        const context = getContext(this) as common.UIAbilityContext;
        const pref = preferences.getPreferencesSync(context, { name: 'health_store' });
        pref.putSync(HISTORY_KEY, '[]');
        pref.flush();
        this.records = [];
        this.getUIContext().getPromptAction().showToast({ message: '历史记录已清空' });
    }
    formatDateTime(ts: number): string {
        const d = new Date(ts);
        const pad = (n: number): string => (n < 10 ? '0' + n : '' + n);
        return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) +
            ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds());
    }
    healthText(status: number): string {
        switch (status) {
            case 1:
                return '正常';
            case 2:
                return '过热';
            case 3:
                return '过压';
            case 4:
                return '低温';
            case 5:
                return '僵死';
            default:
                return '未知';
        }
    }
    healthColor(status: number): string {
        switch (status) {
            case 1:
                return '#2AB676';
            case 2:
            case 3:
                return '#F5A623';
            case 4:
                return '#4A90D9';
            case 5:
                return '#E64545';
            default:
                return '#999999';
        }
    }
    formatBytes(bytes: number): string {
        if (bytes <= 0) {
            return '未知';
        }
        const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
        let v: number = bytes;
        let i: number = 0;
        while (v >= 1024 && i < units.length - 1) {
            v = v / 1024;
            i++;
        }
        return v.toFixed(1) + ' ' + units[i];
    }
    formatTemp(d: number): string {
        return (d / 10).toFixed(1) + ' °C';
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width('100%');
            Column.height('100%');
            Column.backgroundColor('#F1F3F5');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
            Row.padding({ left: 16, right: 16, top: 12, bottom: 8 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('历史记录');
            Text.fontSize(20);
            Text.fontWeight(FontWeight.Bold);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('清空');
            Button.fontSize(13);
            Button.height(32);
            Button.backgroundColor('#E64545');
            Button.onClick(() => {
                this.clearAll();
            });
        }, Button);
        Button.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.records.length === 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.width('100%');
                        Column.layoutWeight(1);
                        Column.justifyContent(FlexAlign.Center);
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('暂无历史记录');
                        Text.fontSize(14);
                        Text.fontColor('#999999');
                    }, Text);
                    Text.pop();
                    Column.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        List.create({ space: 10 });
                        List.width('100%');
                        List.layoutWeight(1);
                        List.padding({ left: 16, right: 16, bottom: 16 });
                    }, List);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const rec = _item;
                            {
                                const itemCreation = (elmtId, isInitialRender) => {
                                    ViewStackProcessor.StartGetAccessRecordingFor(elmtId);
                                    ListItem.create(deepRenderFunction, true);
                                    if (!isInitialRender) {
                                        ListItem.pop();
                                    }
                                    ViewStackProcessor.StopGetAccessRecording();
                                };
                                const itemCreation2 = (elmtId, isInitialRender) => {
                                    ListItem.create(deepRenderFunction, true);
                                };
                                const deepRenderFunction = (elmtId, isInitialRender) => {
                                    itemCreation(elmtId, isInitialRender);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Column.create({ space: 6 });
                                        Column.padding(14);
                                        Column.width('100%');
                                        Column.backgroundColor(Color.White);
                                        Column.borderRadius(12);
                                    }, Column);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Row.create();
                                        Row.width('100%');
                                    }, Row);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Text.create(this.formatDateTime(rec.timestamp));
                                        Text.fontSize(14);
                                        Text.fontWeight(FontWeight.Medium);
                                    }, Text);
                                    Text.pop();
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Blank.create();
                                    }, Blank);
                                    Blank.pop();
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Text.create('🔋 ' + rec.soc + '%');
                                        Text.fontSize(14);
                                        Text.fontWeight(FontWeight.Bold);
                                        Text.fontColor(rec.soc <= 20 ? '#E64545' : (rec.soc <= 50 ? '#F5A623' : '#2AB676'));
                                    }, Text);
                                    Text.pop();
                                    Row.pop();
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Row.create();
                                        Row.width('100%');
                                    }, Row);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Text.create('健康: ' + this.healthText(rec.healthStatus));
                                        Text.fontSize(12);
                                        Text.fontColor(this.healthColor(rec.healthStatus));
                                    }, Text);
                                    Text.pop();
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Blank.create();
                                    }, Blank);
                                    Blank.pop();
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Text.create(this.formatTemp(rec.temperature) + ' · ' +
                                            (rec.voltage / 1000000).toFixed(3) + 'V');
                                        Text.fontSize(12);
                                        Text.fontColor('#888888');
                                    }, Text);
                                    Text.pop();
                                    Row.pop();
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Row.create();
                                        Row.width('100%');
                                    }, Row);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Text.create('存储: 已用 ' + this.formatBytes(rec.totalSize - rec.freeSize) +
                                            ' / 可用 ' + this.formatBytes(rec.freeSize));
                                        Text.fontSize(12);
                                        Text.fontColor('#666666');
                                    }, Text);
                                    Text.pop();
                                    Row.pop();
                                    Column.pop();
                                    ListItem.pop();
                                };
                                this.observeComponentCreation2(itemCreation2, ListItem);
                                ListItem.pop();
                            }
                        };
                        this.forEachUpdateFunction(elmtId, this.records, forEachItemGenFunction, (rec: HistoryRecord) => rec.timestamp + '', false, false);
                    }, ForEach);
                    ForEach.pop();
                    List.pop();
                });
            }
        }, If);
        If.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "HistoryPage";
    }
}
registerNamedRoute(() => new HistoryPage(undefined, {}), "", { bundleName: "io.mnnkeep.harmony", moduleName: "entry", pagePath: "pages/HistoryPage", pageFullPath: "entry/src/main/ets/pages/HistoryPage", integratedHsp: "false", moduleType: "followWithHap" });
