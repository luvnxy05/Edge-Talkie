import batteryInfo from "@ohos:batteryInfo";
import deviceInfo from "@ohos:deviceInfo";
import type { BusinessError } from "@ohos:base";
import storageStatistics from "@ohos:file.storageStatistics";
import type { BatterySnapshot, DeviceSnapshot, StorageSnapshot } from '../model/HealthData';
/**
 * 硬件信息采集器：电池 / 存储 / 设备信息（全部使用普通应用可用的公开 API）
 */
export class DeviceScanner {
    /** 电池快照（同步，属性均为普通应用可读） */
    static scanBattery(): BatterySnapshot {
        let isPresent: boolean = false;
        try {
            isPresent = batteryInfo.isBatteryPresent;
        }
        catch (err) {
            isPresent = false;
        }
        const snap: BatterySnapshot = {
            soc: batteryInfo.batterySOC,
            chargingStatus: batteryInfo.chargingStatus,
            healthStatus: batteryInfo.healthStatus,
            pluggedType: batteryInfo.pluggedType,
            voltage: batteryInfo.voltage,
            temperature: batteryInfo.batteryTemperature,
            current: batteryInfo.nowCurrent,
            technology: batteryInfo.technology,
            isPresent: isPresent,
            capacityLevel: batteryInfo.batteryCapacityLevel,
            timestamp: Date.now()
        };
        return snap;
    }
    /** 存储快照（内置存储总容量 / 可用空间，API 15+，无需权限） */
    static async scanStorage(): Promise<StorageSnapshot> {
        let total: number = 0;
        let free: number = 0;
        try {
            total = await storageStatistics.getTotalSize();
        }
        catch (err) {
            const e = err as BusinessError;
            console.error('getTotalSize failed: ' + e.code + ' ' + e.message);
        }
        try {
            free = await storageStatistics.getFreeSize();
        }
        catch (err) {
            const e = err as BusinessError;
            console.error('getFreeSize failed: ' + e.code + ' ' + e.message);
        }
        const snap: StorageSnapshot = {
            totalSize: total,
            freeSize: free,
            timestamp: Date.now()
        };
        return snap;
    }
    /** 设备信息（diskSN 需要受限权限 ohos.permission.ACCESS_DISK_PHY_INFO，仅 2in1/PC 返回） */
    static scanDevice(): DeviceSnapshot {
        let diskSN: string = '';
        try {
            diskSN = deviceInfo.diskSN;
        }
        catch (err) {
            diskSN = '';
        }
        const snap: DeviceSnapshot = {
            deviceType: deviceInfo.deviceType,
            marketName: deviceInfo.marketName,
            productModel: deviceInfo.productModel,
            hardwareModel: deviceInfo.hardwareModel,
            osFullName: deviceInfo.osFullName,
            displayVersion: deviceInfo.displayVersion,
            sdkApiVersion: deviceInfo.sdkApiVersion,
            diskSN: diskSN
        };
        return snap;
    }
}
