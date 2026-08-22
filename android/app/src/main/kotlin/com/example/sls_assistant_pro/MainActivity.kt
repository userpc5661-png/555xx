package com.userpc5661.slsdrivernext

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.nearpay.sdk.Environments
import io.nearpay.sdk.NearPay
import io.nearpay.sdk.utils.PaymentText
import io.nearpay.sdk.utils.enums.AuthenticationData
import io.nearpay.sdk.utils.enums.NetworkConfiguration
import io.nearpay.sdk.utils.enums.PurchaseFailure
import io.nearpay.sdk.utils.enums.TransactionData
import io.nearpay.sdk.utils.enums.UIPosition
import io.nearpay.sdk.utils.listeners.PurchaseListener
import java.util.Locale
import java.util.UUID

class MainActivity : FlutterActivity() {
    private lateinit var nearPay: NearPay
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        nearPay = NearPay.Builder()
            .context(this)
            .authenticationData(AuthenticationData.UserEnter)
            .environment(Environments.PRODUCTION)
            .locale(Locale.getDefault())
            .networkConfiguration(NetworkConfiguration.DEFAULT)
            .uiPosition(UIPosition.CENTER_BOTTOM)
            .paymentText(PaymentText("يرجى تمرير البطاقة", "please tap your card"))
            .loadingUi(true)
            .build()

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sls_assistant_pro/softpos"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "purchase" -> {
                    if (pendingResult != null) {
                        result.error("busy", "توجد عملية دفع أخرى قيد التنفيذ.", null)
                        return@setMethodCallHandler
                    }
                    val amount = call.argument<Number>("amount_halalas")?.toLong() ?: 0L
                    val reference = call.argument<String>("order_reference")?.trim()
                    if (amount <= 0L) {
                        result.error("invalid_amount", "مبلغ الدفع غير صالح.", null)
                        return@setMethodCallHandler
                    }
                    pendingResult = result
                    startPurchase(amount, reference)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sls_assistant_pro/sms"
        ).setMethodCallHandler { call, result ->
            if (call.method != "compose") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val recipient = call.argument<String>("recipient")?.trim().orEmpty()
            val body = call.argument<String>("body").orEmpty()
            if (recipient.isEmpty()) {
                result.error("invalid_recipient", "رقم العميل غير صالح.", null)
                return@setMethodCallHandler
            }
            try {
                val intent = Intent(Intent.ACTION_SENDTO).apply {
                    data = Uri.parse("smsto:${Uri.encode(recipient)}")
                    putExtra("sms_body", body)
                }
                startActivity(intent)
                result.success(true)
            } catch (_: Throwable) {
                result.success(false)
            }
        }
    }

    private fun startPurchase(amount: Long, reference: String?) {
        nearPay.purchase(
            amount,
            reference?.takeIf { it.isNotEmpty() },
            true,
            true,
            10L,
            UUID.randomUUID(),
            true,
            object : PurchaseListener {
                override fun onPurchaseApproved(transactionData: TransactionData) {
                    val reflected = reflectTransaction(transactionData)
                    finishSuccess(
                        hashMapOf(
                            "success" to true,
                            "cancelled" to false,
                            "message" to "Payment Success",
                            "transaction_id" to firstValue(reflected, "uuid", "transactionUuid", "id"),
                            "card_scheme" to firstValue(reflected, "cardScheme", "schemeName", "scheme"),
                            "amount" to amount,
                            "udid" to firstValue(reflected, "udid", "deviceId"),
                            "gateway_response" to reflected,
                            "card_name" to firstValue(reflected, "cardName", "cardholderName"),
                            "card_number" to firstValue(reflected, "cardNumber", "pan", "maskedPan"),
                            "tid" to firstValue(reflected, "tid", "terminalId"),
                            "qr_code" to firstValue(reflected, "qrCode", "qr_code"),
                            "is_approved" to true
                        )
                    )
                }

                override fun onPurchaseFailed(purchaseFailure: PurchaseFailure) {
                    val name = purchaseFailure.javaClass.simpleName
                    val cancelled = name.contains("cancel", ignoreCase = true) ||
                        name.contains("dismiss", ignoreCase = true)
                    finishSuccess(
                        hashMapOf(
                            "success" to false,
                            "cancelled" to cancelled,
                            "message" to purchaseFailure.toString()
                        )
                    )
                }
            }
        )
    }

    private fun reflectTransaction(value: Any): HashMap<String, Any?> {
        val output = hashMapOf<String, Any?>()
        value.javaClass.methods
            .filter { it.parameterCount == 0 && it.name.startsWith("get") && it.name != "getClass" }
            .forEach { method ->
                try {
                    val key = method.name.removePrefix("get").replaceFirstChar { it.lowercase() }
                    val raw = method.invoke(value)
                    output[key] = when (raw) {
                        null, is String, is Number, is Boolean -> raw
                        else -> raw.toString()
                    }
                } catch (_: Throwable) {
                    // Ignore optional receipt fields that cannot be read.
                }
            }
        output["raw"] = value.toString()
        return output
    }

    private fun firstValue(map: Map<String, Any?>, vararg keys: String): String? {
        for (key in keys) {
            val value = map[key]?.toString()?.trim()
            if (!value.isNullOrEmpty() && value != "null") return value
        }
        return null
    }

    private fun finishSuccess(payload: HashMap<String, Any?>) {
        runOnUiThread {
            pendingResult?.success(payload)
            pendingResult = null
        }
    }
}
