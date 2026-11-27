// SPDX-License-Identifier: GPL-3.0-or-later
//
// iOS-Teil von rosenweg_basis (Kanal "ch.rosenweg4303.basis", wie Android):
//
//  - geraetKennung  identifierForVendor (gleich fuer alle Rosenweg-Apps auf diesem iPhone)
//  - geraetName     "iPhone" / "iPad"
//  - nfcDa          Core NFC nutzbar? (Geraet kann es UND die App hat die Berechtigung)
//  - karteLesen     Rosenweg-Karte (UniFi Access) lesen: nur die UID, als Hex wie Android
//  - qrDa           VisionKit-Scanner nutzbar? (iOS 16+, Kamera erlaubt)
//  - qrScannen      Kamera mit QR-Erkennung als eigenes Fenster; Inhalt oder nil
//
// Die App braucht dafuer (siehe docs/anmeldeschirm.md):
//  - Info.plist NFCReaderUsageDescription, NSCameraUsageDescription
//  - Berechtigung com.apple.developer.nfc.readersession.formats = [TAG]
//    (braucht ein bezahltes Apple-Entwicklerkonto; ohne sie meldet nfcDa false
//    bzw. die Lesesitzung bricht sofort ab, und der Schirm blendet die Karte aus)
import CoreNFC
import Flutter
import UIKit
#if canImport(VisionKit)
import VisionKit
#endif

public class RosenwegBasisPlugin: NSObject, FlutterPlugin {
  private var leser: NfcLeser?
  private var scanner: AnyObject?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let kanal = FlutterMethodChannel(name: "ch.rosenweg4303.basis", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(RosenwegBasisPlugin(), channel: kanal)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "geraetKennung":
      result(UIDevice.current.identifierForVendor?.uuidString)
    case "geraetName":
      result(UIDevice.current.model)
    case "nfcDa":
      result(NFCTagReaderSession.readingAvailable)
    case "karteLesen":
      let hinweis = (call.arguments as? [String: Any])?["hinweis"] as? String ?? "Rosenweg-Karte ans iPhone halten"
      guard NFCTagReaderSession.readingAvailable else {
        result(nil)
        return
      }
      leser?.beenden()
      let l = NfcLeser { [weak self] uid in
        self?.leser = nil
        result(uid)
      }
      leser = l
      l.starten(hinweis)
    case "qrDa":
      if #available(iOS 16.0, *) {
        result(DataScannerViewController.isSupported && DataScannerViewController.isAvailable)
      } else {
        result(false)
      }
    case "qrScannen":
      if #available(iOS 16.0, *), let oben = RosenwegBasisPlugin.obersterSchirm() {
        let s = QrScanner { [weak self] inhalt in
          self?.scanner = nil
          result(inhalt)
        }
        scanner = s
        s.zeigen(von: oben)
      } else {
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static func obersterSchirm() -> UIViewController? {
    let fenster = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var vc = fenster?.rootViewController
    while let p = vc?.presentedViewController { vc = p }
    return vc
  }
}

/// Eine Lesesitzung: erste Karte -> UID (Hex, gross), sonst nil.
final class NfcLeser: NSObject, NFCTagReaderSessionDelegate {
  private var sitzung: NFCTagReaderSession?
  private var fertig: ((String?) -> Void)?

  init(fertig: @escaping (String?) -> Void) {
    self.fertig = fertig
  }

  func starten(_ hinweis: String) {
    // ISO 14443 (MIFARE/DESFire der UniFi-Access-Karten) und ISO 15693; FeliCa
    // braucht Systemcodes in der Info.plist und kommt hier nicht vor.
    sitzung = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: nil)
    sitzung?.alertMessage = hinweis
    sitzung?.begin()
  }

  func beenden() {
    sitzung?.invalidate()
    melden(nil)
  }

  private func melden(_ uid: String?) {
    let f = fertig
    fertig = nil
    DispatchQueue.main.async { f?(uid) }
  }

  func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

  func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
    melden(nil)
  }

  func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
    guard let tag = tags.first else { return }
    let id: Data
    switch tag {
    case .miFare(let t): id = t.identifier
    case .iso7816(let t): id = t.identifier
    case .iso15693(let t): id = t.identifier
    case .feliCa(let t): id = t.currentIDm
    @unknown default:
      session.invalidate(errorMessage: "Diese Karte kann das iPhone nicht lesen.")
      return
    }
    guard !id.isEmpty else {
      session.invalidate(errorMessage: "Karte nicht lesbar – bitte nochmals.")
      return
    }
    let uid = id.map { String(format: "%02X", $0) }.joined()
    session.alertMessage = "Karte erkannt"
    melden(uid)
    session.invalidate()
  }
}

#if canImport(VisionKit)
/// Kamera mit QR-Erkennung (VisionKit), Vollbild mit "Abbrechen"; schliesst
/// beim ersten QR-Code oder nach 60 s (wie der Android-Schirm).
@available(iOS 16.0, *)
final class QrScanner: NSObject, DataScannerViewControllerDelegate {
  private var fertig: ((String?) -> Void)?
  private weak var kamera: DataScannerViewController?
  private var zeit: Timer?

  init(fertig: @escaping (String?) -> Void) {
    self.fertig = fertig
  }

  func zeigen(von oben: UIViewController) {
    let k = DataScannerViewController(
      recognizedDataTypes: [.barcode(symbologies: [.qr])],
      qualityLevel: .balanced,
      recognizesMultipleItems: false,
      isHighFrameRateTrackingEnabled: false,
      isHighlightingEnabled: true)
    k.delegate = self
    k.navigationItem.title = "QR-Code scannen"
    k.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Abbrechen", style: .plain, target: self, action: #selector(abbrechen))
    kamera = k
    let nav = UINavigationController(rootViewController: k)
    nav.modalPresentationStyle = .fullScreen
    oben.present(nav, animated: true) {
      do {
        try k.startScanning()
      } catch {
        self.schliessen(nil)
      }
    }
    zeit = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in self?.schliessen(nil) }
  }

  func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
    for i in addedItems {
      if case .barcode(let b) = i, let text = b.payloadStringValue {
        schliessen(text)
        return
      }
    }
  }

  @objc func abbrechen() {
    schliessen(nil)
  }

  private func schliessen(_ inhalt: String?) {
    guard let f = fertig else { return }
    fertig = nil
    zeit?.invalidate()
    kamera?.stopScanning()
    let nav = kamera?.navigationController
    if let nav = nav {
      nav.dismiss(animated: true) { f(inhalt) }
    } else {
      f(inhalt)
    }
  }
}
#endif
