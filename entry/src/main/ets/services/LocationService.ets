import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';

const APPROXIMATE_LOCATION: Permissions = 'ohos.permission.APPROXIMATELY_LOCATION';

export interface UserLocation {
  latitude: number;
  longitude: number;
  cityName: string;
}

interface BasicLocation {
  latitude: number;
  longitude: number;
}

export class LocationService {
  async requestApproximateLocation(context: common.UIAbilityContext): Promise<UserLocation> {
    await this.ensureLocationPermission(context);
    const location = await this.readDeviceLocation();
    const cityName = await this.reverseGeocodeCity(location.latitude, location.longitude);
    return {
      latitude: location.latitude,
      longitude: location.longitude,
      cityName
    };
  }

  private async ensureLocationPermission(context: common.UIAbilityContext): Promise<void> {
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
  }

  private async readDeviceLocation(): Promise<BasicLocation> {
    try {
      const cachedLocation = geoLocationManager.getLastLocation();
      if (this.isValidCoordinate(cachedLocation.latitude, cachedLocation.longitude)) {
        return {
          latitude: cachedLocation.latitude,
          longitude: cachedLocation.longitude
        };
      }
    } catch (error) {
    }

    const requestInfo: geoLocationManager.CurrentLocationRequest = {
      priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
      scenario: geoLocationManager.LocationRequestScenario.UNSET,
      maxAccuracy: 5000
    };
    try {
      const location = await geoLocationManager.getCurrentLocation(requestInfo);
      return {
        latitude: location.latitude,
        longitude: location.longitude
      };
    } catch (error) {
      throw new Error('暂时无法获取当前位置，可手动搜索城市');
    }
  }

  private isValidCoordinate(latitude: number, longitude: number): boolean {
    return !isNaN(latitude) && !isNaN(longitude) &&
      latitude >= -90 && latitude <= 90 &&
      longitude >= -180 && longitude <= 180 &&
      !(latitude === 0 && longitude === 0);
  }

  private async reverseGeocodeCity(latitude: number, longitude: number): Promise<string> {
    try {
      if (!geoLocationManager.isGeocoderAvailable()) {
        return '';
      }
    } catch (error) {
      return '';
    }

    const reverseGeocodeRequest: geoLocationManager.ReverseGeoCodeRequest = {
      latitude,
      longitude,
      maxItems: 1
    };
    return new Promise<string>((resolve: (cityName: string) => void) => {
      try {
        geoLocationManager.getAddressesFromLocation(reverseGeocodeRequest, (err, data) => {
          if (data === undefined || data === null || data.length === 0) {
            resolve('');
            return;
          }
          const loc = data[0];
          const locality = loc.locality === undefined || loc.locality === null ? '' : String(loc.locality);
          resolve(locality.trim());
        });
      } catch (error) {
        resolve('');
      }
    });
  }
}
