import Foundation
import ObjcFIT
import SwiftFIT

/// Decodes and displays FIT file data, specialized for scuba diving activities
struct FITFileDecoder {
    let filePath: String

    init(filePath: String) {
        self.filePath = filePath
    }

    /// Decodes the FIT file and prints both structured and raw data
    func decode() throws {
        let decoder = FITDecoder()
        let listener = FITListener()
        decoder.mesgDelegate = listener

        guard decoder.decodeFile(filePath) else {
            throw FITDecoderError.decodeFailed
        }

        let messages = listener.messages

        // Print structured dive data
        printStructuredData(messages)

        // Print raw data for debugging
        printRawData(messages)
    }

    // MARK: - Structured Data Output

    private func printStructuredData(_ messages: FITMessages) {
        print("\n" + String(repeating: "=", count: 80))
        print("STRUCTURED DIVE DATA")
        print(String(repeating: "=", count: 80))

        // File ID
        let fileIdMesgs = messages.getFileIdMesgs()
        if !fileIdMesgs.isEmpty {
            print("\n--- File Info ---")
            for mesg in fileIdMesgs {
                if mesg.isTypeValid() {
                    print("Type: \(mesg.getType())")
                }
                if mesg.isManufacturerValid() {
                    print("Manufacturer: \(mesg.getManufacturer())")
                }
                if mesg.isProductValid() {
                    print("Product: \(mesg.getProduct())")
                }
                if mesg.isProductNameValid() {
                    print("Product Name: \(mesg.getProductName())")
                }
                if mesg.isGarminProductValid() {
                    print("Garmin Product: \(mesg.getGarminProduct())")
                }
                if mesg.isSerialNumberValid() {
                    print("Serial Number: \(mesg.getSerialNumber())")
                }
                if mesg.isTimeCreatedValid() {
                    print("Time Created: \(formatTimestamp(mesg.getTimeCreated()))")
                }
            }
        }

        // Device Info
        let deviceInfoMesgs = messages.getDeviceInfoMesgs()
        if !deviceInfoMesgs.isEmpty {
            print("\n--- Device Info ---")
            for mesg in deviceInfoMesgs {
                if mesg.isManufacturerValid() {
                    print("Manufacturer: \(mesg.getManufacturer())")
                }
                if mesg.isProductValid() {
                    print("Product: \(mesg.getProduct())")
                }
                if mesg.isProductNameValid() {
                    print("Product Name: \(mesg.getProductName())")
                }
                if mesg.isGarminProductValid() {
                    print("Garmin Product: \(mesg.getGarminProduct())")
                }
                if mesg.isSoftwareVersionValid() {
                    print("Software Version: \(mesg.getSoftwareVersion())")
                }
                if mesg.isBatteryVoltageValid() {
                    print("Battery Voltage: \(mesg.getBatteryVoltage()) V")
                }
                if mesg.isBatteryStatusValid() {
                    print("Battery Status: \(mesg.getBatteryStatus())")
                }
            }
        }

        // Activity Summary
        let activityMesgs = messages.getActivityMesgs()
        if !activityMesgs.isEmpty {
            print("\n--- Activity Summary ---")
            for mesg in activityMesgs {
                if mesg.isTimestampValid() {
                    print("Timestamp: \(formatTimestamp(mesg.getTimestamp()))")
                }
                if mesg.isTotalTimerTimeValid() {
                    print("Total Timer Time: \(formatDuration(mesg.getTotalTimerTime()))")
                }
                if mesg.isNumSessionsValid() {
                    print("Number of Sessions: \(mesg.getNumSessions())")
                }
                if mesg.isTypeValid() {
                    print("Activity Type: \(mesg.getType())")
                }
                if mesg.isEventValid() {
                    print("Event: \(mesg.getEvent())")
                }
                if mesg.isEventTypeValid() {
                    print("Event Type: \(mesg.getEventType())")
                }
            }
        }

        // Session Data (contains dive summary)
        let sessionMesgs = messages.getSessionMesgs()
        if !sessionMesgs.isEmpty {
            print("\n--- Session/Dive Summary ---")
            for (index, mesg) in sessionMesgs.enumerated() {
                print("\nSession \(index + 1):")
                if mesg.isStartTimeValid() {
                    print("  Start Time: \(formatTimestamp(mesg.getStartTime()))")
                }
                if mesg.isTotalElapsedTimeValid() {
                    print("  Total Elapsed Time: \(formatDuration(mesg.getTotalElapsedTime()))")
                }
                if mesg.isTotalTimerTimeValid() {
                    print("  Total Timer Time: \(formatDuration(mesg.getTotalTimerTime()))")
                }
                if mesg.isSportValid() {
                    print("  Sport: \(mesg.getSport())")
                }
                if mesg.isSubSportValid() {
                    print("  Sub Sport: \(mesg.getSubSport())")
                }
                // Dive-specific fields
                if mesg.isAvgDepthValid() {
                    print("  Avg Depth: \(String(format: "%.2f", mesg.getAvgDepth())) m")
                }
                if mesg.isMaxDepthValid() {
                    print("  Max Depth: \(String(format: "%.2f", mesg.getMaxDepth())) m")
                }
                if mesg.isAvgTemperatureValid() {
                    print("  Avg Temperature: \(mesg.getAvgTemperature()) °C")
                }
                if mesg.isMaxTemperatureValid() {
                    print("  Max Temperature: \(mesg.getMaxTemperature()) °C")
                }
                if mesg.isMinTemperatureValid() {
                    print("  Min Temperature: \(mesg.getMinTemperature()) °C")
                }
                if mesg.isAvgHeartRateValid() {
                    print("  Avg Heart Rate: \(mesg.getAvgHeartRate()) bpm")
                }
                if mesg.isMaxHeartRateValid() {
                    print("  Max Heart Rate: \(mesg.getMaxHeartRate()) bpm")
                }
                if mesg.isTotalCaloriesValid() {
                    print("  Total Calories: \(mesg.getTotalCalories()) kcal")
                }
                // Location
                if mesg.isStartPositionLatValid() && mesg.isStartPositionLongValid() {
                    let lat = Double(mesg.getStartPositionLat()) / 11930465.0
                    let lon = Double(mesg.getStartPositionLong()) / 11930465.0
                    print(
                        "  Start Position: \(String(format: "%.6f", lat)), \(String(format: "%.6f", lon))"
                    )
                }
            }
        }

        // Lap Data (dive segments)
        let lapMesgs = messages.getLapMesgs()
        if !lapMesgs.isEmpty {
            print("\n--- Lap/Segment Data ---")
            for (index, mesg) in lapMesgs.enumerated() {
                print("\nLap \(index + 1):")
                if mesg.isStartTimeValid() {
                    print("  Start Time: \(formatTimestamp(mesg.getStartTime()))")
                }
                if mesg.isTotalElapsedTimeValid() {
                    print("  Elapsed Time: \(formatDuration(mesg.getTotalElapsedTime()))")
                }
                if mesg.isAvgDepthValid() {
                    print("  Avg Depth: \(String(format: "%.2f", mesg.getAvgDepth())) m")
                }
                if mesg.isMaxDepthValid() {
                    print("  Max Depth: \(String(format: "%.2f", mesg.getMaxDepth())) m")
                }
                if mesg.isAvgTemperatureValid() {
                    print("  Avg Temperature: \(mesg.getAvgTemperature()) °C")
                }
                if mesg.isMinTemperatureValid() {
                    print("  Min Temperature: \(mesg.getMinTemperature()) °C")
                }
                if mesg.isMaxTemperatureValid() {
                    print("  Max Temperature: \(mesg.getMaxTemperature()) °C")
                }
            }
        }

        // Record Data (time-series depth/temperature samples with dive metrics)
        let recordMesgs = messages.getRecordMesgs()
        if !recordMesgs.isEmpty {
            print("\n--- Dive Profile Records (\(recordMesgs.count) samples) ---")
            print("Showing key dive metrics per record:")
            print(String(repeating: "-", count: 100))

            // Print first 10 and last 10 records if there are many
            let recordsToShow: [(Int, FITRecordMesg)]
            if recordMesgs.count > 20 {
                let first10 = recordMesgs.prefix(10).enumerated().map { ($0, $1) }
                let last10 = recordMesgs.suffix(10).enumerated().map {
                    (recordMesgs.count - 10 + $0, $1)
                }
                recordsToShow = first10 + [(-1, recordMesgs[0])] + last10
            } else {
                recordsToShow = recordMesgs.enumerated().map { ($0, $1) }
            }

            for (index, mesg) in recordsToShow {
                if index == -1 {
                    print("\n... (\(recordMesgs.count - 20) more records) ...\n")
                    continue
                }

                var parts: [String] = []

                if mesg.isTimestampValid() {
                    parts.append("Time: \(formatTimestamp(mesg.getTimestamp()))")
                }
                if mesg.isDepthValid() {
                    parts.append(String(format: "Depth: %.2fm", mesg.getDepth()))
                }
                if mesg.isTemperatureValid() {
                    parts.append("Temp: \(mesg.getTemperature())°C")
                }
                if mesg.isHeartRateValid() {
                    parts.append("HR: \(mesg.getHeartRate())bpm")
                }
                if mesg.isPo2Valid() {
                    parts.append(String(format: "PO2: %.2f", mesg.getPo2()))
                }
                // Dive-specific record fields
                if mesg.isN2LoadValid() {
                    parts.append("N2: \(mesg.getN2Load())%")
                }
                if mesg.isCnsLoadValid() {
                    parts.append("CNS: \(mesg.getCnsLoad())%")
                }
                if mesg.isNextStopDepthValid() {
                    parts.append(String(format: "NextStop: %.1fm", mesg.getNextStopDepth()))
                }
                if mesg.isNextStopTimeValid() {
                    parts.append("StopTime: \(mesg.getNextStopTime())s")
                }
                if mesg.isTimeToSurfaceValid() {
                    parts.append("TTS: \(mesg.getTimeToSurface())s")
                }
                if mesg.isNdlTimeValid() {
                    parts.append("NDL: \(mesg.getNdlTime())s")
                }

                print("[\(index + 1)] " + parts.joined(separator: " | "))
            }
        }

        // Event Messages (dive alerts, gas switches, etc.)
        let eventMesgs = messages.getEventMesgs()
        if !eventMesgs.isEmpty {
            print("\n--- Events/Alerts ---")
            for (index, mesg) in eventMesgs.enumerated() {
                var parts: [String] = ["[\(index + 1)]"]
                if mesg.isTimestampValid() {
                    parts.append(formatTimestamp(mesg.getTimestamp()))
                }
                if mesg.isEventValid() {
                    parts.append("Event: \(mesg.getEvent())")
                }
                if mesg.isEventTypeValid() {
                    parts.append("Type: \(mesg.getEventType())")
                }
                if mesg.isDataValid() {
                    parts.append("Data: \(mesg.getData())")
                }
                print(parts.joined(separator: " | "))
            }
        }

        // Dive Gas (tank/gas mix info)
        let diveGasMesgs = messages.getDiveGasMesgs()
        if !diveGasMesgs.isEmpty {
            print("\n--- Dive Gas/Tank Info ---")
            for (index, mesg) in diveGasMesgs.enumerated() {
                print("\nGas Mix \(index + 1):")
                if mesg.isMessageIndexValid() {
                    print("  Message Index: \(mesg.getMessageIndex())")
                }
                if mesg.isHeliumContentValid() {
                    print("  Helium: \(mesg.getHeliumContent())%")
                }
                if mesg.isOxygenContentValid() {
                    print("  Oxygen: \(mesg.getOxygenContent())%")
                }
                if mesg.isStatusValid() {
                    print("  Status: \(mesg.getStatus())")
                }
                if mesg.isModeValid() {
                    print("  Mode: \(mesg.getMode())")
                }
            }
        }

        // Dive Summary
        let diveSummaryMesgs = messages.getDiveSummaryMesgs()
        if !diveSummaryMesgs.isEmpty {
            print("\n--- Dive Summary ---")
            for mesg in diveSummaryMesgs {
                if mesg.isDiveNumberValid() {
                    print("Dive Number: \(mesg.getDiveNumber())")
                }
                if mesg.isAvgDepthValid() {
                    print("Avg Depth: \(String(format: "%.2f", mesg.getAvgDepth())) m")
                }
                if mesg.isMaxDepthValid() {
                    print("Max Depth: \(String(format: "%.2f", mesg.getMaxDepth())) m")
                }
                if mesg.isBottomTimeValid() {
                    print("Bottom Time: \(formatDuration(mesg.getBottomTime()))")
                }
                if mesg.isSurfaceIntervalValid() {
                    print("Surface Interval: \(mesg.getSurfaceInterval()) s")
                }
                if mesg.isStartCnsValid() {
                    print("Start CNS: \(mesg.getStartCns())%")
                }
                if mesg.isEndCnsValid() {
                    print("End CNS: \(mesg.getEndCns())%")
                }
                if mesg.isStartN2Valid() {
                    print("Start N2: \(mesg.getStartN2())%")
                }
                if mesg.isEndN2Valid() {
                    print("End N2: \(mesg.getEndN2())%")
                }
                if mesg.isO2ToxicityValid() {
                    print("O2 Toxicity: \(mesg.getO2Toxicity()) OTU")
                }
                if mesg.isAvgAscentRateValid() {
                    print("Avg Ascent Rate: \(String(format: "%.3f", mesg.getAvgAscentRate())) m/s")
                }
                if mesg.isAvgDescentRateValid() {
                    print(
                        "Avg Descent Rate: \(String(format: "%.3f", mesg.getAvgDescentRate())) m/s")
                }
                if mesg.isMaxAscentRateValid() {
                    print("Max Ascent Rate: \(String(format: "%.3f", mesg.getMaxAscentRate())) m/s")
                }
                if mesg.isMaxDescentRateValid() {
                    print(
                        "Max Descent Rate: \(String(format: "%.3f", mesg.getMaxDescentRate())) m/s")
                }
            }
        }

        // Dive Alarm
        let diveAlarmMesgs = messages.getDiveAlarmMesgs()
        if !diveAlarmMesgs.isEmpty {
            print("\n--- Dive Alarms ---")
            for (index, mesg) in diveAlarmMesgs.enumerated() {
                print("\nAlarm \(index + 1):")
                if mesg.isMessageIndexValid() {
                    print("  Message Index: \(mesg.getMessageIndex())")
                }
                if mesg.isDepthValid() {
                    print("  Depth: \(String(format: "%.2f", mesg.getDepth())) m")
                }
                if mesg.isTimeValid() {
                    print("  Time: \(mesg.getTime()) s")
                }
                if mesg.isEnabledValid() {
                    print("  Enabled: \(mesg.getEnabled())")
                }
                if mesg.isAlarmTypeValid() {
                    print("  Alarm Type: \(mesg.getAlarmType())")
                }
                if mesg.isSoundValid() {
                    print("  Sound: \(mesg.getSound())")
                }
            }
        }

        // Dive Settings
        let diveSettingsMesgs = messages.getDiveSettingsMesgs()
        if !diveSettingsMesgs.isEmpty {
            print("\n--- Dive Settings ---")
            for mesg in diveSettingsMesgs {
                if mesg.isNameValid() {
                    print("Name: \(mesg.getName())")
                }
                if mesg.isModelValid() {
                    print("Deco Model: \(mesg.getModel())")
                }
                if mesg.isGfLowValid() {
                    print("GF Low: \(mesg.getGfLow())%")
                }
                if mesg.isGfHighValid() {
                    print("GF High: \(mesg.getGfHigh())%")
                }
                if mesg.isWaterTypeValid() {
                    print("Water Type: \(mesg.getWaterType())")
                }
                if mesg.isWaterDensityValid() {
                    print("Water Density: \(mesg.getWaterDensity()) kg/m³")
                }
                if mesg.isPo2WarnValid() {
                    print("PO2 Warning: \(String(format: "%.2f", mesg.getPo2Warn()))")
                }
                if mesg.isPo2CriticalValid() {
                    print("PO2 Critical: \(String(format: "%.2f", mesg.getPo2Critical()))")
                }
                if mesg.isPo2DecoValid() {
                    print("PO2 Deco: \(String(format: "%.2f", mesg.getPo2Deco()))")
                }
                if mesg.isSafetyStopEnabledValid() {
                    print("Safety Stop Enabled: \(mesg.getSafetyStopEnabled())")
                }
                if mesg.isSafetyStopTimeValid() {
                    print("Safety Stop Time: \(mesg.getSafetyStopTime()) s")
                }
                if mesg.isBottomDepthValid() {
                    print("Bottom Depth: \(String(format: "%.2f", mesg.getBottomDepth())) m")
                }
                if mesg.isBottomTimeValid() {
                    print("Bottom Time: \(mesg.getBottomTime()) s")
                }
                if mesg.isApneaCountdownEnabledValid() {
                    print("Apnea Countdown Enabled: \(mesg.getApneaCountdownEnabled())")
                }
                if mesg.isApneaCountdownTimeValid() {
                    print("Apnea Countdown Time: \(mesg.getApneaCountdownTime()) s")
                }
                if mesg.isBacklightModeValid() {
                    print("Backlight Mode: \(mesg.getBacklightMode())")
                }
                if mesg.isBacklightBrightnessValid() {
                    print("Backlight Brightness: \(mesg.getBacklightBrightness())%")
                }
                if mesg.isBacklightTimeoutValid() {
                    print("Backlight Timeout: \(mesg.getBacklightTimeout())")
                }
                if mesg.isRepeatDiveIntervalValid() {
                    print("Repeat Dive Interval: \(mesg.getRepeatDiveInterval()) s")
                }
                if mesg.isHeartRateSourceTypeValid() {
                    print("Heart Rate Source Type: \(mesg.getHeartRateSourceType())")
                }
                // CCR-related settings
                if mesg.isCcrLowSetpointSwitchModeValid() {
                    print("CCR Low Setpoint Switch Mode: \(mesg.getCcrLowSetpointSwitchMode())")
                }
                if mesg.isCcrLowSetpointValid() {
                    print("CCR Low Setpoint: \(String(format: "%.2f", mesg.getCcrLowSetpoint()))")
                }
                if mesg.isCcrLowSetpointDepthValid() {
                    print(
                        "CCR Low Setpoint Depth: \(String(format: "%.1f", mesg.getCcrLowSetpointDepth())) m"
                    )
                }
                if mesg.isCcrHighSetpointSwitchModeValid() {
                    print("CCR High Setpoint Switch Mode: \(mesg.getCcrHighSetpointSwitchMode())")
                }
                if mesg.isCcrHighSetpointValid() {
                    print("CCR High Setpoint: \(String(format: "%.2f", mesg.getCcrHighSetpoint()))")
                }
                if mesg.isCcrHighSetpointDepthValid() {
                    print(
                        "CCR High Setpoint Depth: \(String(format: "%.1f", mesg.getCcrHighSetpointDepth())) m"
                    )
                }
            }
        }

        // Tank Update (real-time tank pressure readings)
        let tankUpdateMesgs = messages.getTankUpdateMesgs()
        if !tankUpdateMesgs.isEmpty {
            print("\n--- Tank Pressure Updates (\(tankUpdateMesgs.count) readings) ---")
            for (index, mesg) in tankUpdateMesgs.prefix(20).enumerated() {
                var parts: [String] = ["[\(index + 1)]"]
                if mesg.isTimestampValid() {
                    parts.append(formatTimestamp(mesg.getTimestamp()))
                }
                if mesg.isSensorValid() {
                    parts.append("Sensor: \(mesg.getSensor())")
                }
                if mesg.isPressureValid() {
                    parts.append(String(format: "Pressure: %.1f bar", mesg.getPressure()))
                }
                print(parts.joined(separator: " | "))
            }
            if tankUpdateMesgs.count > 20 {
                print("... and \(tankUpdateMesgs.count - 20) more readings")
            }
        }

        // Tank Summary
        let tankSummaryMesgs = messages.getTankSummaryMesgs()
        if !tankSummaryMesgs.isEmpty {
            print("\n--- Tank Summary ---")
            for (index, mesg) in tankSummaryMesgs.enumerated() {
                print("\nTank \(index + 1):")
                if mesg.isSensorValid() {
                    print("  Sensor: \(mesg.getSensor())")
                }
                if mesg.isStartPressureValid() {
                    print(
                        "  Start Pressure: \(String(format: "%.1f", mesg.getStartPressure())) bar")
                }
                if mesg.isEndPressureValid() {
                    print("  End Pressure: \(String(format: "%.1f", mesg.getEndPressure())) bar")
                }
                if mesg.isVolumeUsedValid() {
                    print("  Volume Used: \(String(format: "%.1f", mesg.getVolumeUsed())) L")
                }
            }
        }
    }

    // MARK: - Raw Data Output

    private func printRawData(_ messages: FITMessages) {
        print("\n" + String(repeating: "=", count: 80))
        print("RAW DATA (ALL MESSAGES)")
        print(String(repeating: "=", count: 80))

        // Call all getter methods to get message arrays - comprehensive list
        let messageArrays: [(String, [Any])] = [
            ("FileId", messages.getFileIdMesgs()),
            ("FileCreator", messages.getFileCreatorMesgs()),
            ("Software", messages.getSoftwareMesgs()),
            ("DeviceSettings", messages.getDeviceSettingsMesgs()),
            ("UserProfile", messages.getUserProfileMesgs()),
            ("Sport", messages.getSportMesgs()),
            ("ZonesTarget", messages.getZonesTargetMesgs()),
            ("DiveSettings", messages.getDiveSettingsMesgs()),
            ("DiveAlarm", messages.getDiveAlarmMesgs()),
            ("DiveApneaAlarm", messages.getDiveApneaAlarmMesgs()),
            ("DiveGas", messages.getDiveGasMesgs()),
            ("Goal", messages.getGoalMesgs()),
            ("Activity", messages.getActivityMesgs()),
            ("Session", messages.getSessionMesgs()),
            ("Lap", messages.getLapMesgs()),
            ("Length", messages.getLengthMesgs()),
            ("Record", messages.getRecordMesgs()),
            ("Event", messages.getEventMesgs()),
            ("DeviceInfo", messages.getDeviceInfoMesgs()),
            ("DiveSummary", messages.getDiveSummaryMesgs()),
            ("TankUpdate", messages.getTankUpdateMesgs()),
            ("TankSummary", messages.getTankSummaryMesgs()),
            ("FieldDescription", messages.getFieldDescriptionMesgs()),
            ("DeveloperDataId", messages.getDeveloperDataIdMesgs()),
        ]

        for (name, array) in messageArrays {
            guard !array.isEmpty else { continue }

            let suffix: String
            let elementsToShow: [(Int, Any)]
            if name == "Record" && array.count > 20 {
                let first10 = array.prefix(10).enumerated().map { ($0, $1) }
                let last10 = array.suffix(10).enumerated().map {
                    (array.count - 10 + $0, $1)
                }
                elementsToShow = first10 + [(-1, array[0])] + last10
                suffix = " (showing first 10, last 10)"
            } else {
                elementsToShow = array.enumerated().map { ($0, $1) }
                suffix = ""
            }

            print("\n--- \(name) (\(array.count) messages)\(suffix) ---")

            for (index, element) in elementsToShow {
                if index == -1 {
                    print("\n... (\(array.count - 20) more records) ...\n")
                    continue
                }
                print("\n[\(index + 1)]")
                printAllValidFields(element)
            }
        }
    }

    /// Prints all valid fields from a FIT message by checking isXxxValid() methods
    private func printAllValidFields(_ message: Any) {
        guard let fitMessage = message as? NSObject else { return }

        var methodCount: UInt32 = 0
        guard let methods = class_copyMethodList(type(of: fitMessage), &methodCount) else {
            return
        }
        defer { free(methods) }

        // Collect all isXxxValid method names
        var validatorMethods: [String] = []
        for i in 0..<Int(methodCount) {
            let selector = method_getName(methods[i])
            let name = NSStringFromSelector(selector)
            if name.hasPrefix("is") && name.hasSuffix("Valid") && !name.contains(":") {
                validatorMethods.append(name)
            }
        }

        var fields: [(String, String)] = []

        for validatorName in validatorMethods {
            let validatorSelector = NSSelectorFromString(validatorName)

            guard isValidField(fitMessage, selector: validatorSelector) else { continue }

            // Extract field name from isXxxValid -> Xxx
            let fieldName = String(validatorName.dropFirst(2).dropLast(5))

            // Construct getter name: Xxx -> getXxx
            let getterName = "get\(fieldName)"
            let getterSelector = NSSelectorFromString(getterName)

            guard let valueStr = getValueString(fitMessage, selector: getterSelector) else {
                continue
            }
            fields.append((fieldName, valueStr))
        }

        // Sort and print fields
        for (name, value) in fields.sorted(by: { $0.0 < $1.0 }) {
            print("  \(name): \(value)")
        }
    }

    // MARK: - Helpers

    private func methodReturnEncoding(_ method: Method) -> String {
        var buffer = [CChar](repeating: 0, count: 128)
        method_getReturnType(method, &buffer, 128)
        return buffer.withUnsafeBufferPointer { ptr in
            String(validatingCString: ptr.baseAddress!) ?? ""
        }
    }

    private func isValidField(_ obj: NSObject, selector: Selector) -> Bool {
        guard let method = class_getInstanceMethod(type(of: obj), selector) else {
            return false
        }
        let encoding = methodReturnEncoding(method)
        let imp = method_getImplementation(method)

        switch encoding {
        case "B":
            typealias Func = @convention(c) (AnyObject, Selector) -> Bool
            return unsafeBitCast(imp, to: Func.self)(obj, selector)
        case "c":
            typealias Func = @convention(c) (AnyObject, Selector) -> Int8
            return unsafeBitCast(imp, to: Func.self)(obj, selector) != 0
        case "C":
            typealias Func = @convention(c) (AnyObject, Selector) -> UInt8
            return unsafeBitCast(imp, to: Func.self)(obj, selector) != 0
        case "s":
            typealias Func = @convention(c) (AnyObject, Selector) -> Int16
            return unsafeBitCast(imp, to: Func.self)(obj, selector) != 0
        case "S":
            typealias Func = @convention(c) (AnyObject, Selector) -> UInt16
            return unsafeBitCast(imp, to: Func.self)(obj, selector) != 0
        case "i":
            typealias Func = @convention(c) (AnyObject, Selector) -> Int32
            return unsafeBitCast(imp, to: Func.self)(obj, selector) != 0
        case "I":
            typealias Func = @convention(c) (AnyObject, Selector) -> UInt32
            return unsafeBitCast(imp, to: Func.self)(obj, selector) != 0
        case "l":
            typealias Func = @convention(c) (AnyObject, Selector) -> Int
            return unsafeBitCast(imp, to: Func.self)(obj, selector) != 0
        case "L":
            typealias Func = @convention(c) (AnyObject, Selector) -> UInt
            return unsafeBitCast(imp, to: Func.self)(obj, selector) != 0
        case "q":
            typealias Func = @convention(c) (AnyObject, Selector) -> Int64
            return unsafeBitCast(imp, to: Func.self)(obj, selector) != 0
        case "Q":
            typealias Func = @convention(c) (AnyObject, Selector) -> UInt64
            return unsafeBitCast(imp, to: Func.self)(obj, selector) != 0
        case "f":
            typealias Func = @convention(c) (AnyObject, Selector) -> Float
            return unsafeBitCast(imp, to: Func.self)(obj, selector) != 0
        case "d":
            typealias Func = @convention(c) (AnyObject, Selector) -> Double
            return unsafeBitCast(imp, to: Func.self)(obj, selector) != 0
        default:
            return false
        }
    }

    private func getValueString(_ obj: NSObject, selector: Selector) -> String? {
        guard let method = class_getInstanceMethod(type(of: obj), selector) else {
            return nil
        }
        let encoding = methodReturnEncoding(method)
        let imp = method_getImplementation(method)

        if encoding.hasPrefix("@") || encoding == "#" {
            typealias Func = @convention(c) (AnyObject, Selector) -> AnyObject?
            let value = unsafeBitCast(imp, to: Func.self)(obj, selector)
            if let date = value as? FITDate {
                return formatTimestamp(date)
            }
            return value.map { "\($0)" } ?? "nil"
        }

        switch encoding {
        case "B":
            typealias Func = @convention(c) (AnyObject, Selector) -> Bool
            return unsafeBitCast(imp, to: Func.self)(obj, selector) ? "true" : "false"
        case "c":
            typealias Func = @convention(c) (AnyObject, Selector) -> Int8
            return "\(unsafeBitCast(imp, to: Func.self)(obj, selector))"
        case "C":
            typealias Func = @convention(c) (AnyObject, Selector) -> UInt8
            return "\(unsafeBitCast(imp, to: Func.self)(obj, selector))"
        case "s":
            typealias Func = @convention(c) (AnyObject, Selector) -> Int16
            return "\(unsafeBitCast(imp, to: Func.self)(obj, selector))"
        case "S":
            typealias Func = @convention(c) (AnyObject, Selector) -> UInt16
            return "\(unsafeBitCast(imp, to: Func.self)(obj, selector))"
        case "i":
            typealias Func = @convention(c) (AnyObject, Selector) -> Int32
            return "\(unsafeBitCast(imp, to: Func.self)(obj, selector))"
        case "I":
            typealias Func = @convention(c) (AnyObject, Selector) -> UInt32
            return "\(unsafeBitCast(imp, to: Func.self)(obj, selector))"
        case "l":
            typealias Func = @convention(c) (AnyObject, Selector) -> Int
            return "\(unsafeBitCast(imp, to: Func.self)(obj, selector))"
        case "L":
            typealias Func = @convention(c) (AnyObject, Selector) -> UInt
            return "\(unsafeBitCast(imp, to: Func.self)(obj, selector))"
        case "q":
            typealias Func = @convention(c) (AnyObject, Selector) -> Int64
            return "\(unsafeBitCast(imp, to: Func.self)(obj, selector))"
        case "Q":
            typealias Func = @convention(c) (AnyObject, Selector) -> UInt64
            return "\(unsafeBitCast(imp, to: Func.self)(obj, selector))"
        case "f":
            typealias Func = @convention(c) (AnyObject, Selector) -> Float
            return "\(unsafeBitCast(imp, to: Func.self)(obj, selector))"
        case "d":
            typealias Func = @convention(c) (AnyObject, Selector) -> Double
            return "\(unsafeBitCast(imp, to: Func.self)(obj, selector))"
        default:
            return "<unsupported \(encoding)>"
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private func formatTimestamp(_ timestamp: FITDate) -> String {
        let date = timestamp.date
        return Self.timestampFormatter.string(from: date)
    }

    private func formatDuration(_ seconds: Float32) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

enum FITDecoderError: Error, LocalizedError {
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .decodeFailed:
            return "Failed to decode FIT file"
        }
    }
}
