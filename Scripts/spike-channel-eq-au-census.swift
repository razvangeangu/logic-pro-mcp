#!/usr/bin/env swift
import AudioToolbox
import Foundation

struct JSONRecord: Encodable {
    let record_type: String
    let status: String
    let component_name: String?
    let component_type: String?
    let component_subtype: String?
    let component_manufacturer: String?
    let parameter_id: UInt32?
    let parameter_name: String?
    let min_value: Float?
    let max_value: Float?
    let default_value: Float?
    let unit: UInt32?
    let flags: UInt32?
    let provenance: String
    let activation_evidence: Bool
    let note: String
}

func emit(_ record: JSONRecord) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(record),
          let line = String(data: data, encoding: .utf8) else {
        return
    }
    print(line)
}

func fourCC(_ value: OSType) -> String {
    let bytes = [
        UInt8((value >> 24) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8(value & 0xff),
    ]
    return String(bytes: bytes, encoding: .macOSRoman) ?? "\(value)"
}

func componentName(_ component: AudioComponent) -> String {
    var cfName: Unmanaged<CFString>?
    let status = AudioComponentCopyName(component, &cfName)
    guard status == noErr, let cfName else {
        return "<unnamed>"
    }
    return cfName.takeRetainedValue() as String
}

func parameterName(_ info: AudioUnitParameterInfo) -> String {
    if let cfName = info.cfNameString {
        return cfName.takeUnretainedValue() as String
    }
    return withUnsafePointer(to: info.name) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: 52) {
            String(cString: $0)
        }
    }
}

func enumerateParameters(
    component: AudioComponent,
    name: String,
    description: AudioComponentDescription
) {
    func emitComponentStatus(_ status: String, note: String) {
        emit(JSONRecord(
            record_type: "channel_eq_au_component",
            status: status,
            component_name: name,
            component_type: fourCC(description.componentType),
            component_subtype: fourCC(description.componentSubType),
            component_manufacturer: fourCC(description.componentManufacturer),
            parameter_id: nil,
            parameter_name: nil,
            min_value: nil,
            max_value: nil,
            default_value: nil,
            unit: nil,
            flags: nil,
            provenance: "factory_metadata",
            activation_evidence: false,
            note: note
        ))
    }

    var unit: AudioUnit?
    guard AudioComponentInstanceNew(component, &unit) == noErr, let unit else {
        emitComponentStatus(
            "instantiate_failed",
            note: "Factory metadata cannot prove active Logic insert write/read-back."
        )
        return
    }
    defer { AudioComponentInstanceDispose(unit) }

    var byteSize: UInt32 = 0
    var writable = DarwinBoolean(false)
    let infoStatus = AudioUnitGetPropertyInfo(
        unit,
        kAudioUnitProperty_ParameterList,
        kAudioUnitScope_Global,
        0,
        &byteSize,
        &writable
    )
    guard infoStatus == noErr, byteSize > 0 else {
        emitComponentStatus(
            "no_parameter_list",
            note: "No active Logic insert handle was obtained."
        )
        return
    }

    let parameterIDStride = UInt32(MemoryLayout<AudioUnitParameterID>.stride)
    guard byteSize % parameterIDStride == 0 else {
        emitComponentStatus(
            "parameter_list_size_mismatch",
            note: "AudioUnit parameter list reported \(byteSize) bytes, not a whole AudioUnitParameterID count."
        )
        return
    }

    var parameterIDs = [AudioUnitParameterID](
        repeating: 0,
        count: Int(byteSize / parameterIDStride)
    )
    var listSize = byteSize
    let listStatus = parameterIDs.withUnsafeMutableBufferPointer { buffer in
        guard let baseAddress = buffer.baseAddress else {
            return OSStatus(-50)
        }
        return AudioUnitGetProperty(
            unit,
            kAudioUnitProperty_ParameterList,
            kAudioUnitScope_Global,
            0,
            baseAddress,
            &listSize
        )
    }
    guard listStatus == noErr else {
        emitComponentStatus(
            "parameter_list_read_failed",
            note: "AudioUnitGetProperty(kAudioUnitProperty_ParameterList) failed with OSStatus \(listStatus)."
        )
        return
    }
    guard listSize % parameterIDStride == 0,
          Int(listSize / parameterIDStride) == parameterIDs.count else {
        emitComponentStatus(
            "parameter_list_size_mismatch",
            note: "AudioUnit parameter list returned \(listSize) bytes for \(parameterIDs.count) allocated ids."
        )
        return
    }

    for parameterID in parameterIDs {
        var parameterInfo = AudioUnitParameterInfo()
        var parameterInfoSize = UInt32(MemoryLayout<AudioUnitParameterInfo>.size)
        guard AudioUnitGetProperty(
            unit,
            kAudioUnitProperty_ParameterInfo,
            kAudioUnitScope_Global,
            parameterID,
            &parameterInfo,
            &parameterInfoSize
        ) == noErr else {
            continue
        }
        emit(JSONRecord(
            record_type: "channel_eq_au_parameter",
            status: "factory_metadata_only",
            component_name: name,
            component_type: fourCC(description.componentType),
            component_subtype: fourCC(description.componentSubType),
            component_manufacturer: fourCC(description.componentManufacturer),
            parameter_id: parameterID,
            parameter_name: parameterName(parameterInfo),
            min_value: parameterInfo.minValue,
            max_value: parameterInfo.maxValue,
            default_value: parameterInfo.defaultValue,
            unit: parameterInfo.unit.rawValue,
            flags: parameterInfo.flags.rawValue,
            provenance: "factory_metadata",
            activation_evidence: false,
            note: "Candidate id/range only; production activation still requires active Logic insert write/read-back evidence."
        ))
    }
}

var description = AudioComponentDescription(
    componentType: kAudioUnitType_Effect,
    componentSubType: 0,
    componentManufacturer: 0,
    componentFlags: 0,
    componentFlagsMask: 0
)

var found = 0
var current: AudioComponent?
while true {
    current = AudioComponentFindNext(current, &description)
    guard let component = current else { break }
    var actualDescription = AudioComponentDescription()
    guard AudioComponentGetDescription(component, &actualDescription) == noErr else {
        continue
    }
    let name = componentName(component)
    let lower = name.lowercased()
    guard lower.contains("channel eq") || lower.contains("nband") || lower.contains("aunbandeq") else {
        continue
    }
    found += 1
    enumerateParameters(component: component, name: name, description: actualDescription)
}

emit(JSONRecord(
    record_type: "channel_eq_au_census_summary",
    status: found > 0 ? "factory_metadata_only" : "missing",
    component_name: nil,
    component_type: nil,
    component_subtype: nil,
    component_manufacturer: nil,
    parameter_id: nil,
    parameter_name: nil,
    min_value: nil,
    max_value: nil,
    default_value: nil,
    unit: nil,
    flags: nil,
    provenance: "factory_metadata",
    activation_evidence: false,
    note: "This spike never attaches to Logic's active hosted insert; it cannot activate registry entries by itself."
))
