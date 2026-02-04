import Flutter
import UIKit
import AVFoundation

public class CallAudioRoutePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private enum Constants {
    static let methodChannel = "call_audio_route/methods"
    static let eventChannel = "call_audio_route/route_changes"
    static let configureCall = "configureForCall"
    static let stopCallAudio = "stopCallAudio"
  }

  private enum AudioRoute: String {
    case earpiece
    case speaker
    case bluetooth
    case wiredHeadset
    case systemDefault
  }

  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  private let audioSession = AVAudioSession.sharedInstance()
  private var routeOverride: AudioRoute = .systemDefault
  private var isSessionActive = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = CallAudioRoutePlugin()
    let methodChannel = FlutterMethodChannel(name: Constants.methodChannel, binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(name: Constants.eventChannel, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
    instance.methodChannel = methodChannel
    instance.eventChannel = eventChannel

    NotificationCenter.default.addObserver(instance, selector: #selector(instance.handleRouteChange(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
    NotificationCenter.default.addObserver(instance, selector: #selector(instance.handleInterruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setRoute":
      guard let args = call.arguments as? [String: Any], let routeName = args["route"] as? String else {
        result(FlutterError(code: "missing_route", message: "setRoute requires a route name", details: nil))
        return
      }
      setRoute(AudioRoute(rawValue: routeName) ?? .systemDefault)
      result(nil)
    case "getRouteInfo":
      result(routeInfo())
    case Constants.configureCall:
      configureForCall()
      emitRouteInfo()
    case Constants.stopCallAudio:
      stopCallAudio()
      emitRouteInfo()
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    emitRouteInfo()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func setRoute(_ route: AudioRoute) {
    routeOverride = route
    switch route {
    case .systemDefault:
      deactivateSession()
    case .bluetooth:
      activateSession()
      // Bluetooth routing is handled by the system; we only keep the session ready for HFP.
      applyRouteOverride()
    default:
      activateSession()
      applyRouteOverride()
    }
    emitRouteInfo()
  }

  private func configureForCall() {
    activateSession()
    emitRouteInfo()
  }

  private func stopCallAudio() {
    deactivateSession()
  }

  private func activateSession() {
    guard !isSessionActive else { return }
    let options: AVAudioSession.CategoryOptions = [.allowBluetooth]
    // Avoid allowBluetoothA2DP because the HFP voice path is lower latency and more stable for VoIP.
    try? audioSession.setPreferredSampleRate(48_000)
    try? audioSession.setPreferredIOBufferDuration(0.02)
    try? audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: options)
    try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    isSessionActive = true
  }

  private func deactivateSession() {
    guard isSessionActive else { return }
    try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    isSessionActive = false
    routeOverride = .systemDefault
    emitRouteInfo()
  }

  @objc private func handleRouteChange(_ notification: Notification) {
    emitRouteInfo()
  }

  @objc private func handleInterruption(_ notification: Notification) {
    guard let info = notification.userInfo,
          let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
      return
    }

    if type == .ended && isSessionActive {
      try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
      applyRouteOverride()
      emitRouteInfo()
    }
  }

  private func emitRouteInfo() {
    eventSink?(routeInfo())
  }

  private func routeInfo() -> [String: Any] {
    let current = currentRoute()
    var available: [String] = [AudioRoute.earpiece.rawValue, AudioRoute.speaker.rawValue]
    if bluetoothConnected() {
      available.append(AudioRoute.bluetooth.rawValue)
    }
    if wiredConnected() {
      available.append(AudioRoute.wiredHeadset.rawValue)
    }
    if !isSessionActive {
      available.append(AudioRoute.systemDefault.rawValue)
    }

    return [
      "current": current.rawValue,
      "available": available,
      "bluetoothConnected": bluetoothConnected(),
      "wiredConnected": wiredConnected(),
    ]
  }

  private func currentRoute() -> AudioRoute {
    guard isSessionActive else {
      return .systemDefault
    }

    switch routeOverride {
    case .speaker:
      return .speaker
    case .earpiece:
      return .earpiece
    case .wiredHeadset where wiredConnected():
      return .wiredHeadset
    case .bluetooth:
      return .bluetooth
    case .systemDefault, .wiredHeadset:
      break
    }

    if routeOverride != .speaker && bluetoothConnected() {
      return .bluetooth
    }

    if wiredConnected() {
      return .wiredHeadset
    }

    let outputs = audioSession.currentRoute.outputs
    if outputs.contains(where: { $0.portType == .builtInSpeaker }) {
      return .speaker
    }

    return .earpiece
  }

  private func applyRouteOverride() {
    guard isSessionActive else { return }
    switch routeOverride {
    case .speaker:
      try? audioSession.overrideOutputAudioPort(.speaker)
    case .systemDefault:
      try? audioSession.overrideOutputAudioPort(.none)
    case .earpiece, .wiredHeadset, .bluetooth:
      try? audioSession.overrideOutputAudioPort(.none)
    }
  }

  private func bluetoothConnected() -> Bool {
    audioSession.currentRoute.outputs.contains {
      $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP || $0.portType == .bluetoothLE
    }
  }

  private func wiredConnected() -> Bool {
    audioSession.currentRoute.outputs.contains {
      $0.portType == .headphones ||
      $0.portType == .headsetMic ||
      $0.portType == .usbAudio ||
      $0.portType == .lineOut
    }
  }
}
