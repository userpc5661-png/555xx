import Flutter
import MessageUI
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  MFMessageComposeViewControllerDelegate
{
  private var smsChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    smsChannel = FlutterMethodChannel(
      name: "sls_assistant_pro/sms",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    smsChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "compose" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let recipient = arguments["recipient"] as? String,
        !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        result(FlutterError(
          code: "invalid_recipient",
          message: "رقم العميل غير صالح.",
          details: nil
        ))
        return
      }
      let body = arguments["body"] as? String ?? ""
      self?.presentSmsComposer(recipient: recipient, body: body, result: result)
    }
  }

  private func presentSmsComposer(
    recipient: String,
    body: String,
    result: @escaping FlutterResult
  ) {
    guard MFMessageComposeViewController.canSendText() else {
      result(false)
      return
    }
    guard let presenter = topViewController() else {
      result(false)
      return
    }

    let composer = MFMessageComposeViewController()
    composer.messageComposeDelegate = self
    composer.recipients = [recipient]
    composer.body = body
    presenter.present(composer, animated: true) {
      result(true)
    }
  }

  private func topViewController(_ base: UIViewController? = nil) -> UIViewController? {
    let root = base ?? UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }?
      .rootViewController

    if let navigation = root as? UINavigationController {
      return topViewController(navigation.visibleViewController)
    }
    if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
      return topViewController(selected)
    }
    if let presented = root?.presentedViewController {
      return topViewController(presented)
    }
    return root
  }

  func messageComposeViewController(
    _ controller: MFMessageComposeViewController,
    didFinishWith result: MessageComposeResult
  ) {
    controller.dismiss(animated: true)
  }
}
