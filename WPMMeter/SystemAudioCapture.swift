import AVFoundation
import CoreAudio

/// Captures the Mac's mixed output without creating a screen-capture stream.
final class SystemAudioCapture: @unchecked Sendable {
    enum Error: Swift.Error {
        case permissionDenied
        case unavailable
    }

    struct Audio: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        let time: AVAudioTime
    }

    let audio: AsyncStream<Audio>

    private let continuation: AsyncStream<Audio>.Continuation
    private let system = AudioHardwareSystem.shared
    private var tap: AudioHardwareTap?
    private var device: AudioHardwareAggregateDevice?
    private var ioProcID: AudioDeviceIOProcID?

    init() throws {
        var continuation: AsyncStream<Audio>.Continuation!
        audio = AsyncStream(bufferingPolicy: .bufferingOldest(128)) { continuation = $0 }
        self.continuation = continuation

        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "WPM Meter System Audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        if let bundleID = Bundle.main.bundleIdentifier {
            description.bundleIDs = [bundleID]
        }

        do {
            guard let tap = try system.makeProcessTap(description: description) else { throw Error.unavailable }
            self.tap = tap
            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "WPM Meter Audio",
                kAudioAggregateDeviceUIDKey: "\(Bundle.main.bundleIdentifier ?? "WPMMeter").audio.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: try tap.uid]],
            ]
            guard let device = try system.makeAggregateDevice(description: aggregateDescription) else {
                throw Error.unavailable
            }
            self.device = device

            var streamDescription = try tap.format
            guard let format = AVAudioFormat(streamDescription: &streamDescription) else { throw Error.unavailable }
            var ioProcID: AudioDeviceIOProcID?
            let status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, device.id, nil) { [continuation] _, inputData, inputTime, _, _ in
                Self.copy(inputData, format: format, time: inputTime.pointee, to: continuation)
            }
            guard status == noErr, let ioProcID else { throw Self.error(for: status) }
            self.ioProcID = ioProcID
        } catch let error as AudioHardwareError {
            stop()
            throw Self.error(for: error.error)
        } catch {
            stop()
            throw error
        }
    }

    func start() throws {
        guard let device, let ioProcID else { throw Error.unavailable }
        let status = AudioDeviceStart(device.id, ioProcID)
        guard status == noErr else { throw Self.error(for: status) }
    }

    func stop() {
        continuation.finish()
        if let device, let ioProcID {
            AudioDeviceStop(device.id, ioProcID)
            AudioDeviceDestroyIOProcID(device.id, ioProcID)
        }
        ioProcID = nil
        if let device { try? system.destroyAggregateDevice(device) }
        device = nil
        if let tap { try? system.destroyProcessTap(tap) }
        tap = nil
    }

    deinit { stop() }

    private static func copy(
        _ source: UnsafePointer<AudioBufferList>,
        format: AVAudioFormat,
        time: AudioTimeStamp,
        to continuation: AsyncStream<Audio>.Continuation
    ) {
        let sources = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source))
        guard let first = sources.first, format.streamDescription.pointee.mBytesPerFrame > 0 else { return }
        let frames = AVAudioFrameCount(first.mDataByteSize / format.streamDescription.pointee.mBytesPerFrame)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        let destinations = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard sources.count == destinations.count else { return }
        for index in sources.indices {
            guard let sourceData = sources[index].mData, let destinationData = destinations[index].mData else { return }
            let byteCount = min(Int(sources[index].mDataByteSize), Int(destinations[index].mDataByteSize))
            destinationData.copyMemory(from: sourceData, byteCount: byteCount)
        }
        let sampleTime = time.mFlags.contains(.sampleTimeValid) ? AVAudioFramePosition(time.mSampleTime) : 0
        if case .dropped = continuation.yield(Audio(buffer: buffer, time: AVAudioTime(sampleTime: sampleTime, atRate: format.sampleRate))) {
            continuation.finish()
        }
    }

    private static func error(for status: OSStatus) -> Error {
        status == kAudioDevicePermissionsError ? .permissionDenied : .unavailable
    }
}
