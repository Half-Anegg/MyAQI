import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';

const APPROXIMATE_LOCATION: Permissions = 'ohos.permission.APPROXIMATELY_LOCATION';

export interface UserLocation {
  latitude: number;
  longitude: number;
}

export class LocationService {
  async requestApproximateLocation(context: common.UIAbilityContext): Promise<UserLocation> {
    const atManager = abilityAccessCtrl.createAtManager();
    let permissionResult: number[] = [];
    try {
      const result = await atManager.requestPermissionsFromUser(context, [APPROXIMATE_LOCATION]);
      permissionResult = result.authResults;
    } catch (error) {
      throw new Error('定位权限请求失败，可手动搜索城市');
    }
    const granted = permissionResult.length > 0 &&
      permissionResult[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    if (!granted) {
      throw new Error('定位权限未授权，可手动搜索城市');
    }

    const requestInfo: geoLocationManager.CurrentLocationRequest = {
      priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
      scenario: geoLocationManager.LocationRequestScenario.UNSET,
      maxAccuracy: 5000
    };
    let latitude = 0;
    let longitude = 0;
    try {
      const location = await geoLocationManager.getCurrentLocation(requestInfo);
      latitude = location.latitude;
      longitude = location.longitude;
    } catch (error) {
      throw new Error('暂时无法获取当前位置，可手动搜索城市');
    }
    return {
      latitude,
      longitude
    };
  }
}
