import Foundation
import IOKit
#if SWIFT_PACKAGE
import SMCBridge
#endif

class SMCNative {
    static let shared = SMCNative()
    
    private var conn: io_connect_t = 0
    private var validTempKey: String?
    private var validPowerKey: String?
    
    init() {
        if SMCOpen(&conn) == kIOReturnSuccess {
            log("SMC: Connected successfully using kernel interface")
            scanForKeys()
        } else {
            log("SMC: Failed to connect")
        }
    }
    
    deinit {
        SMCClose(conn)
    }

    func readSystemPower() -> Double? {
        guard let key = validPowerKey else { return nil }
        var value: Double = 0
        if SMCReadKey(conn, key, &value) == kIOReturnSuccess {
            return value
        }
        return nil
    }
    
    func readTemperature() -> Double? {
        guard let key = validTempKey else { return nil }
        var value: Double = 0
        if SMCReadKey(conn, key, &value) == kIOReturnSuccess {
            return value
        }
        return nil
    }

    private func scanForKeys() {
        log("SMC: Scanning for valid keys...")
        
        let tempKeys = ["TB0T", "Tp0T", "TC0P", "TC0D", "TC0E", "TC0F", "Th0H", "Tp09", "TN0P", "Ts0P"]
        let powerKeys = ["PSTR", "PDTR", "PCPT", "PC0C", "PCPC"]
        
        for key in tempKeys {
            var value: Double = 0
            if SMCReadKey(conn, key, &value) == kIOReturnSuccess, value > 1.0, value < 110.0 {
                log("SMC: FOUND TEMP: \(key)=\(value)")
                validTempKey = key
                break
            }
        }
        
        for key in powerKeys {
            var value: Double = 0
            if SMCReadKey(conn, key, &value) == kIOReturnSuccess, value > 0.1, value < 300.0 {
                log("SMC: FOUND POWER: \(key)=\(value)")
                validPowerKey = key
                break
            }
        }
        
        if validTempKey == nil { log("SMC: No valid temperature key found") }
        if validPowerKey == nil { log("SMC: No valid power key found") }
    }
    
    private func log(_ msg: String) {
        // Silent - no logging
    }
}