import XCTest
import AVFoundation
import CoreMedia
import os
@testable import OpenPrompter

@MainActor
final class SharedSpeechAudioTests: XCTestCase {
    private final class Backend: SpeechBackend {
        nonisolated let packets = OSAllocatedUnfairLock(initialState: 0)
        var starts = 0
        var stops = 0
        var active = false

        func start(locale: Locale, contextualStrings: [String],
                   onWords: @escaping @MainActor ([String]) -> Void,
                   onTranscription: @escaping @MainActor (String) -> Void,
                   onFinal: @escaping @MainActor () -> Void,
                   onUnavailable: @escaping @MainActor () -> Void,
                   onError: @escaping @MainActor (String) -> Void) -> Bool {
            starts += 1
            active = true
            return true
        }
        func stop() { stops += 1; active = false }
        nonisolated func appendAudioSampleBuffer(_ buffer: CMSampleBuffer) {
            packets.withLock { $0 += 1 }
        }
    }

    private func audioFixture() throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
            mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &format), noErr)
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
            memoryBlock: nil, blockLength: 960, blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil, offsetToData: 0, dataLength: 960, flags: 0,
            blockBufferOut: &block), noErr)
        let audio = try XCTUnwrap(block)
        XCTAssertEqual(CMBlockBufferFillDataBytes(with: 0, blockBuffer: audio, offsetIntoDestination: 0, dataLength: 960), noErr)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault,
            dataBuffer: audio, formatDescription: try XCTUnwrap(format), sampleCount: 480,
            presentationTimeStamp: .zero, packetDescriptions: nil, sampleBufferOut: &sample), noErr)
        let buffer = try XCTUnwrap(sample)
        XCTAssertTrue(CMSampleBufferIsValid(buffer))
        return buffer
    }

    func testSharedBufferForwardingAndIndependentWriterConsumer() async throws {
        let backend = Backend()
        let tracker = VoiceTracker(suppressDeviceWork: true, backendFactory: { backend })
        tracker.prepareTestAuthorization(.authorized)
        tracker.loadScript("hello world")
        let buffer = try audioFixture()
        tracker.feedAudio(buffer)
        XCTAssertEqual(backend.packets.withLock { $0 }, 0)
        XCTAssertTrue(tracker.start())
        XCTAssertTrue(tracker.start())
        XCTAssertEqual(backend.starts, 1)
        // Exercise non-MainActor ingestion with a valid capture-like buffer.
        await Task.detached { tracker.feedAudio(buffer) }.value
        XCTAssertEqual(backend.packets.withLock { $0 }, 1)
        XCTAssertEqual(tracker.audioPacketCount, 1)
        tracker.stop()
        tracker.stop()
        XCTAssertEqual(backend.stops, 1)
        var writerPackets = 0
        let fork: (CMSampleBuffer) -> Void = { tracker.feedAudio($0) }
        fork(buffer)
        writerPackets += 1
        XCTAssertEqual(writerPackets, 1)
        XCTAssertEqual(backend.packets.withLock { $0 }, 1)
        XCTAssertTrue(tracker.start())
        tracker.feedAudio(buffer)
        XCTAssertEqual(backend.starts, 2)
        XCTAssertEqual(backend.packets.withLock { $0 }, 2)
        tracker.stop()
    }

    func testNoAudioFailureDeactivatesAndReportsReason() {
        let backend = Backend()
        let tracker = VoiceTracker(suppressDeviceWork: true, backendFactory: { backend })
        tracker.prepareTestAuthorization(.authorized)
        tracker.loadScript("hello world")
        XCTAssertTrue(tracker.start())
        tracker.failSharedAudio("Shared camera audio is unavailable.")
        XCTAssertFalse(tracker.isActive)
        XCTAssertEqual(tracker.lastFailureReason, "Shared camera audio is unavailable.")
        XCTAssertEqual(backend.stops, 1)
        XCTAssertEqual(PrefKey.voiceUseSpeechAnalyzer.defaultValue as? Bool, false)
    }

    func testSFInactiveIngestionAndStopNeedNoMicrophoneEngine() throws {
        let backend = SFSpeechBackend()
        backend.appendAudioSampleBuffer(try audioFixture())
        backend.stop()
        backend.stop()
    }
}
