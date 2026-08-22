# Changelog — Assistant UI & Task Fixes

## 1.9.13+4

### Fixed
- Shipment reference mapping now prioritizes `order_awb`.
- Delivery coordinates now support `delivery_location_lat` and `delivery_location_lng`.
- Nested task/order payloads are expanded into one visible card per order.
- Location action falls back to the delivery address when coordinates are absent.
- Task diagnostics redact the API token from URLs and sensitive headers.

### Added
- Dashboard, Tasks, Map, and Scanner bottom navigation.
- COD/prepaid and progress filters.
- Daily summary metrics and COD total.
- OpenStreetMap markers with shipment details.
- Dark mode toggle.
- iOS camera and location permission descriptions.
- Task model unit tests for official SLS field names and nested payloads.
