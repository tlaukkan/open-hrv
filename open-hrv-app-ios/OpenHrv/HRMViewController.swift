/**
 * Copyright (c) 2017 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
 * distribute, sublicense, create a derivative work, and/or sell copies of the
 * Software in any work that is designed, intended, or marketed for pedagogical or
 * instructional purposes related to programming, coding, application development,
 * or information technology.  Permission for such use, copying, modification,
 * merger, publication, distribution, sublicensing, creation of derivative works,
 * or sale is expressly withheld.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

import UIKit
import CoreBluetooth

let heartRateServiceCBUUID = CBUUID(string: "0x180D")
let heartRateMeasurementCharacteristicCBUUID = CBUUID(string: "2A37")
let bodySensorLocationCharacteristicCBUUID = CBUUID(string: "2A38")

class HRMViewController: UIViewController {

  @IBOutlet weak var heartRateLabel: UILabel!
  @IBOutlet weak var rrLabel: UILabel!
  @IBOutlet weak var bodySensorLocationLabel: UILabel!

  var centralManager: CBCentralManager!
  var heartRatePeripheral: CBPeripheral!

  override func viewDidLoad() {
    super.viewDidLoad()
    centralManager = CBCentralManager(delegate: self, queue: nil)
    heartRateLabel.font = UIFont.monospacedDigitSystemFont(ofSize: heartRateLabel.font!.pointSize, weight: .regular)
  }
  
  func onBodySensorLocationReceived(_ bodySensorLocation: String) {
    bodySensorLocationLabel.text = bodySensorLocation
  }

  func onHeartRateReceived(_ heartRate: Int, _ rrs:[Int], _ energy: Int) {
    heartRateLabel.text = String(heartRate)
    if (rrs.count > 0) {
      rrLabel.text = String(rrs[0])
    }
    print("BPM: \(heartRate) RRs: \(rrs) Energy: \(energy)")
    postHeartRateData(heartRate: heartRate, rrs: rrs)
  }
  
  var apiUrl: String = "http://192.168.71.107:8080/api"
  var httpSecurityToken: String? = nil
  
  
  private func postHeartRateData(heartRate: Int, rrs: [Int]) {
    if (httpSecurityToken == nil) {
      getSecurityToken()
    } else {
      let url = URL(string: apiUrl + "/health/heartrate")!
      
      var json = [String:Any]()
      
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      
      json["hr"] = heartRate
      json["rrs"] = rrs
      json["time"] = formatter.string(from: Date())
      
      guard let data = try? JSONSerialization.data(withJSONObject: json) else {
        print("Error in JSON serialization of data.")
        return
      }
      
      var request = URLRequest(url: url)
      request.setValue("SecurityToken token='" + httpSecurityToken! + "'", forHTTPHeaderField: "Authorization")
      request.httpMethod = "POST"
      request.httpBody = data
      request.addValue("application/json", forHTTPHeaderField: "Content-Type")
      request.addValue("application/json", forHTTPHeaderField: "Accept")
      
      print("posting to server: " + String(data: data, encoding: String.Encoding.utf8)!)
      
      URLSession.shared.dataTask(with: request) {(data, response, error) in
        if let httpResponse = response as? HTTPURLResponse {
          if (httpResponse.statusCode != 200) {
            print("Error status code \(httpResponse.statusCode)")
            if (httpResponse.statusCode == 401) {
              self.httpSecurityToken = nil
            }
            if (error != nil) {
              print("Error: " + error.debugDescription);
            }
          }
        }
        
        if (data != nil) {
          print(String(data: data!, encoding: String.Encoding.utf8)!)
        }
        }.resume()
    }
  }
  
  private func getSecurityToken() {
    let url = URL(string: apiUrl + "/security/context")!
    var request = URLRequest(url: url)
    
    let credentials = "default.client:password1234"
    let credentialsBase64 = credentials.base64Encoded()!
    
    request.setValue("Basic " + credentialsBase64, forHTTPHeaderField: "Authorization")

    URLSession.shared.dataTask(with: request) {(data, response, error) in
      if let httpResponse = response as? HTTPURLResponse {
        if (httpResponse.statusCode == 200) {
          if let securityToken = httpResponse.allHeaderFields["Security-Token"] as? String {
            let encodedSecurityToken = securityToken.addingPercentEncoding(withAllowedCharacters:NSCharacterSet.alphanumerics)!
            print("received security token: \(securityToken) / \(encodedSecurityToken)")
            self.httpSecurityToken = encodedSecurityToken
          }
        } else {
          print("Error status code \(httpResponse.statusCode)")
          if (error != nil) {
            print("Error: " + error.debugDescription);
          }
        }
      }
      
      if (data != nil) {
        print(String(data: data!, encoding: String.Encoding.utf8)!)
      }
    }.resume()
  }
  
}

extension HRMViewController: CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    switch central.state {
    case .unknown:
      print("central.state is .unknown")
    case .resetting:
      print("central.state is .resetting")
    case .unsupported:
      print("central.state is .unsupported")
    case .unauthorized:
      print("central.state is .unauthorized")
    case .poweredOff:
      print("central.state is .poweredOff")
    case .poweredOn:
      print("central.state is .poweredOn")
      centralManager.scanForPeripherals(withServices: [heartRateServiceCBUUID])
    }
  }

  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                      advertisementData: [String : Any], rssi RSSI: NSNumber) {
    print("Discovered \(peripheral.name ?? "")")
    heartRatePeripheral = peripheral
    heartRatePeripheral.delegate = self
    centralManager.stopScan()
    centralManager.connect(heartRatePeripheral)
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    print("Connected \(peripheral.name ?? "")")
    heartRatePeripheral.discoverServices([heartRateServiceCBUUID])
  }
}

extension HRMViewController: CBPeripheralDelegate {
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard let services = peripheral.services else { return }
    for service in services {
      print(service)
      peripheral.discoverCharacteristics(nil, for: service)
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard let characteristics = service.characteristics else { return }

    for characteristic in characteristics {
      print(characteristic)

      if characteristic.properties.contains(.read) {
        print("\(characteristic.uuid): properties contains .read")
        peripheral.readValue(for: characteristic)
      }
      if characteristic.properties.contains(.notify) {
        print("\(characteristic.uuid): properties contains .notify")
        peripheral.setNotifyValue(true, for: characteristic)
      }
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    if error != nil {
      print("Error in peripheral method: \(error.debugDescription)")
      return
    }
    
    switch characteristic.uuid {
    case bodySensorLocationCharacteristicCBUUID:
      parseBodySensorLocation(characteristic)
    case heartRateMeasurementCharacteristicCBUUID:
      parseHeartRate(characteristic)
    default:
      print("Unhandled Characteristic UUID: \(characteristic.uuid)")
    }
  }

  private func parseBodySensorLocation(_ characteristic: CBCharacteristic) {
    guard let characteristicData = characteristic.value,
      let byte = characteristicData.first else { return; }

    switch byte {
    case 0: onBodySensorLocationReceived("Other"); return
    case 1: onBodySensorLocationReceived("Chest"); return
    case 2: onBodySensorLocationReceived("Wrist"); return
    case 3: onBodySensorLocationReceived("Finger"); return
    case 4: onBodySensorLocationReceived("Hand"); return
    case 5: onBodySensorLocationReceived("Ear Lobe"); return
    case 6: onBodySensorLocationReceived("Foot"); return
    default:
      onBodySensorLocationReceived("Reserved for future use"); return
    }
  }
  
  func parseHeartRate(_ characteristic: CBCharacteristic){
    let data = characteristic.value
    let hrFormat = data![0] & 0x01;
    let energyExpended = (data![0] & 0x08) >> 3;
    let rrPresent = (data![0] & 0x10) >> 4;
    let hrValue = hrFormat == 1 ? (Int(data![1]) + (Int(data![2]) << 8)) : Int(data![1]);
    var offset = Int(hrFormat) + 2;
    var energy = 0
    if (energyExpended == 1) {
      energy = Int(data![offset]) + (Int(data![offset + 1]) << 8);
      offset += 2;
    }
    var rrs = [Int]()
    if( rrPresent == 1 ){
      let len = data!.count
      while (offset < len) {
        let rrValueRaw = Int(data![offset]) | (Int(data![offset + 1]) << 8)
        let rrValue = Int((Double(rrValueRaw) / 1024.0) * 1000.0);
        offset += 2;
        rrs.append(rrValue);
      }
    }
    onHeartRateReceived(hrValue, rrs, energy)
  }
}
