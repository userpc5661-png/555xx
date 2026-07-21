import '../models/scan_models.dart';
import '../services/scan_api_service.dart';

class ScanRepository {
  final ScanApiService _api;

  ScanRepository({required String savedSession, ScanApiService? api})
      : _api = api ?? ScanApiService(savedSession: savedSession);

  Future<LinehaulGroup> scanLinehaulGroup(String code) =>
      _api.scanLinehaulGroup(code);

  Future<ScanActionResult> receiveLinehaulGroups(List<LinehaulGroup> groups) {
    final ids = groups
        .where((group) => group.status.startsWith('Out to Destination'))
        .map((group) => group.id)
        .toList();
    if (ids.isEmpty) {
      throw const ScanApiException(
        'لا توجد مجموعة حالتها Out to Destination ليتم استلامها.',
      );
    }
    return _api.receiveLinehaulGroups(ids);
  }

  Future<ScanActionResult> dispatchLinehaulGroups(List<LinehaulGroup> groups) {
    final ids = groups
        .where((group) => group.status == 'closed')
        .map((group) => group.id)
        .toList();
    if (ids.isEmpty) {
      throw const ScanApiException(
        'لا توجد مجموعة حالتها closed ليتم إرسالها.',
      );
    }
    return _api.dispatchLinehaulGroups(ids);
  }

  Future<ScannedOrderGroup> scanOrderGroup(String code) =>
      _api.scanOrderGroup(code);

  Future<ScannedShipment> scanOrder(String awb) => _api.scanOrder(awb);

  Future<ScanActionResult> confirmOrder({
    required int groupId,
    required int orderId,
    required String orderAwb,
  }) {
    return _api.confirmOrder(
      groupId: groupId,
      orderId: orderId,
      orderAwb: orderAwb,
    );
  }

  Future<ScanActionResult> moveOrderGroupToOfd(int groupId) =>
      _api.moveOrderGroupToOfd(groupId);

  Future<ScanActionResult> addPickupLocation({
    required String location,
    required double latitude,
    required double longitude,
  }) {
    return _api.addPickupLocation(
      location: location,
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<SubTrackingResponse> getSubTrackingNumbers(String value) =>
      _api.getSubTrackingNumbers(value);

  Future<ScanActionResult> completeSubTrackingScan(String value) =>
      _api.completeSubTrackingScan(value);

  Future<ScanActionResult> updateStatus({
    required Map<String, dynamic> officialBody,
    required Object assigneeId,
  }) {
    return _api.updateStatus(
      officialBody: officialBody,
      assigneeId: assigneeId,
    );
  }

  Future<Map<String, dynamic>> getDriverStatuses({
    required bool withoutScan,
    required Object currentStatus,
    required Object currentStatusLabel,
    required Object currentIsRvp,
    required Object currentOrderType,
  }) {
    return _api.getDriverStatuses(
      withoutScan: withoutScan,
      currentStatus: currentStatus,
      currentStatusLabel: currentStatusLabel,
      currentIsRvp: currentIsRvp,
      currentOrderType: currentOrderType,
    );
  }

  Future<ScanActionResult> updateDriverLocation(
    DriverLocationRequest request,
  ) {
    return _api.updateDriverLocation(request);
  }

  Future<List<SequencerOrder>> getSequencerOddOrders() =>
      _api.getSequencerOddOrders();
}
