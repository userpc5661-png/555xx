# تحويل الخريطة إلى OpenStreetMap

- إزالة `google_maps_flutter` وكل متطلبات مفتاح Google Maps وBilling وSHA-1.
- إضافة `flutter_map` و`latlong2`.
- استخدام خرائط OpenStreetMap داخل التطبيق بلا API Key.
- استمرار تحديث موقع المندوب مباشرة عبر `Geolocator.getPositionStream`.
- عرض موقع المندوب كنقطة زرقاء وعملاء المهام كعلامات منفصلة.
- الضغط على علامة العميل يفتح تفاصيل الشحنة التي تتضمن اسم المتجر والعميل ورقم الشحنة والهاتف والعنوان.
- الإبقاء على أزرار إظهار جميع العملاء وإعادة تمركز الخريطة على موقع المندوب.
- إضافة نسبة المصدر `© OpenStreetMap contributors` داخل الخريطة.

## التشغيل

```bash
flutter clean
flutter pub get
flutter build apk --release
```

لا تضف `GOOGLE_MAPS_API_KEY`؛ لم يعد مطلوبًا.
