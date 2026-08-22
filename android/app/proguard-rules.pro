# Project-specific R8 rules.
# Flutter plugins bundled by this project publish their own consumer rules;
# keep this file present because the release build explicitly references it.

# OkHttp probes these optional TLS providers only when an application installs
# them. SLS Assistant uses Android's platform TLS provider, so R8 can safely
# ignore their absence instead of failing the release build.
-dontwarn org.bouncycastle.jsse.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
