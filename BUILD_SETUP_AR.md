# تشغيل المشروع بعد فك الضغط

1. افتح مجلد المشروع الرئيسي في Android Studio، وليس مجلد `android` وحده.
2. تأكد أن Flutter SDK وAndroid SDK معرفان في Android Studio.
3. نفذ داخل Terminal:

```powershell
flutter clean
flutter pub get
flutter doctor -v
flutter run
```

## ما تم إصلاحه

- إزالة `shared_preferences` التي كانت تجلب سلسلة Native Assets تتضمن `jni` و`jni_flutter` في ملف القفل السابق.
- نقل التخزين المحلي المستخدم في تصحيح الموقع وسجل التواصل إلى `flutter_secure_storage` الموجودة أصلًا بالمشروع.
- إضافة Kotlin Android plugin صراحةً في `android/app/build.gradle.kts`.
- حذف ملفات البناء والكاش وملف `local.properties` المرتبط بجهاز المطور السابق.
- حذف `pubspec.lock` القديم لكي يعيد Flutter حل التبعيات من `pubspec.yaml` النظيف.

## ملاحظة

ملف `android/local.properties` يُنشأ عادة تلقائيًا عند فتح المشروع وتشغيل `flutter pub get`. يوجد ملف مثال باسم `android/local.properties.example` عند الحاجة.
