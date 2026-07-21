import 'api_config.dart';

class ScanApiConfig {
  ScanApiConfig._();

  static const String linehaulGroup = '${ApiConfig.baseUrl}/linehaul/group';
  static const String receiveLinehaul = '${ApiConfig.baseUrl}/linehaul/receive';
  static const String dispatchLinehaul =
      '${ApiConfig.baseUrl}/linehaul/dispatch';
  static const String orderGroups = '${ApiConfig.baseUrl}/order-groups';
  static const String confirmOrder = '$orderGroups/confirm-order';
  static const String ofd = '$orderGroups/ofd';
  static const String ordersByAwb = '${ApiConfig.baseUrl}/orders/awb';
  static const String bulkStatus = '${ApiConfig.baseUrl}/orders/bulk/status';
  static const String addPickupLocation =
      '${ApiConfig.baseUrl}/add-pickup-location';
  static const String subTrackingNumbers =
      '${ApiConfig.baseUrl}/sub-tracking-numbers';
  static const String completeSubTrackingScan =
      '${ApiConfig.baseUrl}/sub-tracking/update-completed-scan';
  static const String driverStatuses =
      '${ApiConfig.baseUrl}/statuses/driver-statuses';
  static const String driverStatusesWithoutScan =
      '${ApiConfig.baseUrl}/statuses/driver-statuses-without-scan';
  static const String driverLocation =
      '${ApiConfig.baseUrl}/driver-location/add';
  static const String sequencerOddOrders =
      '${ApiConfig.baseUrl}/sequencer-odd-orders';
}
