import Testing
@testable import ConsaiCore

@Suite struct ContainerImageTests {

    @Test func idIsTheReference() {
        let image = ContainerImage(reference: "alpine:3.20", digest: "sha256:abcd")
        #expect(image.id == "alpine:3.20")
    }

    @Test func shortDigestStripsPrefixAndTruncatesTo12() {
        let image = ContainerImage(reference: "alpine", digest: "sha256:abcd1234efgh5678ijkl")
        #expect(image.shortDigest == "abcd1234efgh")
    }

    @Test func shortDigestHandlesBareHex() {
        let image = ContainerImage(reference: "alpine", digest: "abcdef1234567890")
        #expect(image.shortDigest == "abcdef123456")
    }

    @Test func formattedSizeIsNilWithoutAUsableSize() {
        #expect(ContainerImage(reference: "a", digest: "d", sizeBytes: nil).formattedSize == nil)
        #expect(ContainerImage(reference: "a", digest: "d", sizeBytes: 0).formattedSize == nil)
        #expect(ContainerImage(reference: "a", digest: "d", sizeBytes: -5).formattedSize == nil)
    }

    @Test func formattedSizeUsesSIBinaryBoundaries() {
        #expect(formatImageBytes(2_500_000_000) == "2.50 GB")
        #expect(formatImageBytes(1_000_000_000) == "1.00 GB")
        #expect(formatImageBytes(234_000_000) == "234 MB")
        #expect(formatImageBytes(512_000) == "512 KB")
    }
}
