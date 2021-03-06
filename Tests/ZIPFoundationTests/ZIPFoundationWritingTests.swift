//
//  ZIPFoundationWritingTests.swift
//  ZIPFoundation
//
//  Copyright © 2017 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/LICENSE for license information.
//

import XCTest
@testable import ZIPFoundation

extension ZIPFoundationTests {
    func testCreateArchiveAddUncompressedEntry() {
        let archive = self.archive(for: #function, mode: .create)
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        do {
            let relativePath = assetURL.lastPathComponent
            let baseURL = assetURL.deletingLastPathComponent()
            try archive.addEntry(with: relativePath, relativeTo: baseURL)
        } catch {
            XCTFail("Failed to add entry to uncompressed folder archive with error : \(error)")
        }
        XCTAssert(archive.checkIntegrity())
    }

    func testCreateArchiveAddCompressedEntry() {
        let archive = self.archive(for: #function, mode: .create)
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        do {
            let relativePath = assetURL.lastPathComponent
            let baseURL = assetURL.deletingLastPathComponent()
            try archive.addEntry(with: relativePath, relativeTo: baseURL, compressionMethod: .deflate)
        } catch {
            XCTFail("Failed to add entry to uncompressed folder archive with error : \(error)")
        }
        let entry = archive[assetURL.lastPathComponent]
        XCTAssertNotNil(entry)
        XCTAssert(archive.checkIntegrity())
    }

    func testCreateArchiveAddDirectory() {
        let archive = self.archive(for: #function, mode: .create)
        do {
            try archive.addEntry(with: "Test",
                                 type: .directory,
                                 uncompressedSize: 0,
                                 provider: { _, _ in return Data()})
        } catch {
            XCTFail("Failed to add directory entry without file system representation to archive.")
        }
        let testEntry = archive["Test"]
        XCTAssertNotNil(testEntry)
        let uniqueString = ProcessInfo.processInfo.globallyUniqueString
        let tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(uniqueString)
        do {
            let fileManager = FileManager()
            try fileManager.createDirectory(at: tempDirectoryURL,
                                            withIntermediateDirectories: true,
                                            attributes: nil)
            let relativePath = tempDirectoryURL.lastPathComponent
            let baseURL = tempDirectoryURL.deletingLastPathComponent()
            try archive.addEntry(with: relativePath + "/", relativeTo: baseURL)
        } catch {
            XCTFail("Failed to add directory entry to archive.")
        }
        let entry = archive[tempDirectoryURL.lastPathComponent + "/"]
        XCTAssertNotNil(entry)
        XCTAssert(archive.checkIntegrity())
    }

    func testCreateArchiveAddSymbolicLink() {
        let archive = self.archive(for: #function, mode: .create)
        let rootDirectoryURL = ZIPFoundationTests.tempZipDirectoryURL.appendingPathComponent("SymbolicLinkDirectory")
        let symbolicLinkURL = rootDirectoryURL.appendingPathComponent("test.link")
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        let fileManager = FileManager()
        do {
            try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            try fileManager.createSymbolicLink(atPath: symbolicLinkURL.path, withDestinationPath: assetURL.path)
            let relativePath = symbolicLinkURL.lastPathComponent
            let baseURL = symbolicLinkURL.deletingLastPathComponent()
            try archive.addEntry(with: relativePath, relativeTo: baseURL)
        } catch {
            XCTFail("Failed to add symbolic link to archive")
        }
        let entry = archive[symbolicLinkURL.lastPathComponent]
        XCTAssertNotNil(entry)
        XCTAssert(archive.checkIntegrity())
        do {
            try archive.addEntry(with: "link", type: .symlink, uncompressedSize: 10, provider: { (_, count) -> Data in
                return Data(count: count)
            })
        } catch {
            XCTFail("Failed to add symbolic link to archive")
        }
        let entry2 = archive["link"]
        XCTAssertNotNil(entry2)
        XCTAssert(archive.checkIntegrity())
    }

    func testCreateArchiveAddEntryErrorConditions() {
        var didCatchExpectedError = false
        let archive = self.archive(for: #function, mode: .create)
        let tempPath = NSTemporaryDirectory()
        var nonExistantURL = URL(fileURLWithPath: tempPath)
        nonExistantURL.appendPathComponent("invalid.path")
        let nonExistantRelativePath = nonExistantURL.lastPathComponent
        let nonExistantBaseURL = nonExistantURL.deletingLastPathComponent()
        do {
            try archive.addEntry(with: nonExistantRelativePath, relativeTo: nonExistantBaseURL)
        } catch let error as CocoaError {
            XCTAssert(error.code == .fileReadNoSuchFile)
            didCatchExpectedError = true
        } catch {
            XCTFail("Unexpected error while trying to add non-existant file to an archive.")
        }
        XCTAssertTrue(didCatchExpectedError)
    }

    func testArchiveAddEntryErrorConditions() {
        var didCatchExpectedError = false
        let readonlyArchive = self.archive(for: #function, mode: .read)
        do {
            try readonlyArchive.addEntry(with: "Test", type: .directory,
                                         uncompressedSize: 0, provider: { _, _ in return Data()})
        } catch let error as Archive.ArchiveError {
            XCTAssert(error == .unwritableArchive)
            didCatchExpectedError = true
        } catch {
            XCTFail("Unexpected error while trying to add an entry to a readonly archive.")
        }
        XCTAssertTrue(didCatchExpectedError)
    }

    func testCreateArchiveAddLargeUncompressedEntry() {
        let archive = self.archive(for: #function, mode: .create)
        let size = 1024*1024*20
        let data = Data.makeRandomData(size: size)
        let entryName = ProcessInfo.processInfo.globallyUniqueString
        do {
            try archive.addEntry(with: entryName, type: .file,
                                 uncompressedSize: UInt32(size), provider: { (position, bufferSize) -> Data in
                                    let upperBound = Swift.min(size, position + bufferSize)
                                    let range = Range(uncheckedBounds: (lower: position, upper: upperBound))
                                    return data.subdata(in: range)
            })
        } catch {
            XCTFail("Failed to add large entry to uncompressed archive with error : \(error)")
        }
        guard let entry = archive[entryName] else {
            XCTFail("Failed to add large entry to uncompressed archive")
            return
        }
        XCTAssert(entry.checksum == data.crc32(checksum: 0))
        XCTAssert(archive.checkIntegrity())
    }

    func testCreateArchiveAddLargeCompressedEntry() {
        let archive = self.archive(for: #function, mode: .create)
        let size = 1024*1024*20
        let data = Data.makeRandomData(size: size)
        let entryName = ProcessInfo.processInfo.globallyUniqueString
        do {
            try archive.addEntry(with: entryName, type: .file,
                                 uncompressedSize: UInt32(size),
                                 compressionMethod: .deflate,
                                 provider: { (position, bufferSize) -> Data in
                                    let upperBound = Swift.min(size, position + bufferSize)
                                    let range = Range(uncheckedBounds: (lower: position, upper: upperBound))
                                    return data.subdata(in: range)
            })
        } catch {
            XCTFail("Failed to add large entry to compressed archive with error : \(error)")
        }
        guard let entry = archive[entryName] else {
            XCTFail("Failed to add large entry to compressed archive")
            return
        }
        let dataCRC32 = data.crc32(checksum: 0)
        XCTAssert(entry.checksum == dataCRC32)
        XCTAssert(archive.checkIntegrity())
    }

    func testCreateArchiveAddTooLargeUncompressedEntry() {
        let archive = self.archive(for: #function, mode: .create)
        let fileName = ProcessInfo.processInfo.globallyUniqueString
        var didCatchExpectedError = false
        do {
            try archive.addEntry(with: fileName,
                                 type: .file,
                                 uncompressedSize: UINT32_MAX,
                                 provider: { (_, chunkSize) -> Data in
                return Data.makeRandomData(size: chunkSize)
            })
        } catch let error as Archive.ArchiveError {
            XCTAssertNotNil(error == .invalidStartOfCentralDirectoryOffset)
            didCatchExpectedError = true
        } catch {
            XCTFail("Unexpected error while trying to remove entry from unwritable archive.")
        }
        XCTAssert(didCatchExpectedError)
    }

    func testRemoveUncompressedEntry() {
        let archive = self.archive(for: #function, mode: .update)
        guard let entryToRemove = archive["test/data.random"] else {
            XCTFail("Failed to find entry to remove in uncompressed folder")
            return
        }
        do {
            try archive.remove(entryToRemove)
        } catch {
            XCTFail("Failed to remove entry from uncompressed folder archive with error : \(error)")
        }
        XCTAssert(archive.checkIntegrity())
    }

    func testRemoveCompressedEntry() {
        let archive = self.archive(for: #function, mode: .update)
        guard let entryToRemove = archive["test/data.random"] else {
            XCTFail("Failed to find entry to remove in compressed folder archive")
            return
        }
        do {
            try archive.remove(entryToRemove)
        } catch {
            XCTFail("Failed to remove entry from compressed folder archive with error : \(error)")
        }
        XCTAssert(archive.checkIntegrity())
    }

    func testRemoveDataDescriptorCompressedEntry() {
        let archive = self.archive(for: #function, mode: .update)
        guard let entryToRemove = archive["second.txt"] else {
            XCTFail("Failed to find entry to remove in compressed folder archive")
            return
        }
        do {
            try archive.remove(entryToRemove)
        } catch {
            XCTFail("Failed to remove entry to compressed folder archive with error : \(error)")
        }
        XCTAssert(archive.checkIntegrity())
    }

    func testRemoveEntryErrorConditions() {
        var didCatchExpectedError = false
        let archive = self.archive(for: #function, mode: .update)
        guard let entryToRemove = archive["test/data.random"] else {
            XCTFail("Failed to find entry to remove in uncompressed folder")
            return
        }
        // We don't have access to the temp archive file that Archive.remove
        // uses. To exercise the error code path, we temporarily limit the number of open files for
        // the test process to exercise the error code path here.
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        let fileNoFlag = RLIMIT_NOFILE
#else
        let fileNoFlag = Int32(RLIMIT_NOFILE.rawValue)
#endif
        var storedRlimit = rlimit()
        getrlimit(fileNoFlag, &storedRlimit)
        var tempRlimit = storedRlimit
        tempRlimit.rlim_cur = rlim_t(0)
        setrlimit(fileNoFlag, &tempRlimit)
        do {
            try archive.remove(entryToRemove)
        } catch let error as Archive.ArchiveError {
            XCTAssertNotNil(error == .unwritableArchive)
            didCatchExpectedError = true
        } catch {
            XCTFail("Unexpected error while trying to remove entry from unwritable archive.")
        }
        setrlimit(fileNoFlag, &storedRlimit)
        XCTAssertTrue(didCatchExpectedError)
    }

    func testFileModificationDate() {
        var testDateComponents = DateComponents()
        testDateComponents.calendar = Calendar(identifier: Calendar.Identifier.gregorian)
        testDateComponents.timeZone = TimeZone(identifier: "UTC")
        testDateComponents.year = 2000
        testDateComponents.month = 1
        testDateComponents.day = 1
        testDateComponents.hour = 12
        testDateComponents.minute = 30
        testDateComponents.second = 10
        guard let testDate = testDateComponents.date else {
            XCTFail("Failed to create test date/timestamp")
            return
        }
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        let fileManager = FileManager()
        let archive = self.archive(for: #function, mode: .create)
        do {
            try fileManager.setAttributes([.modificationDate: testDate], ofItemAtPath: assetURL.path)
            let relativePath = assetURL.lastPathComponent
            let baseURL = assetURL.deletingLastPathComponent()
            try archive.addEntry(with: relativePath, relativeTo: baseURL)
            guard let entry = archive["\(assetURL.lastPathComponent)"] else {
                throw Archive.ArchiveError.unreadableArchive
            }
            guard let fileDate = entry.fileAttributes[.modificationDate] as? Date else {
                throw CocoaError(CocoaError.fileReadUnknown)
            }
            let currentTimeInterval = testDate.timeIntervalSinceReferenceDate
            let fileTimeInterval = fileDate.timeIntervalSinceReferenceDate
            // ZIP uses MSDOS timestamps, which provide very poor accuracy
            // https://blogs.msdn.microsoft.com/oldnewthing/20151030-00/?p=91881
            XCTAssertEqual(currentTimeInterval, fileTimeInterval, accuracy: 2.0)
        } catch {
            XCTFail("Failed to test last file modification date")
        }
    }

    func testPOSIXPermissions() {
        let permissions = Int16(0o753)
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        let fileManager = FileManager()
        let archive = self.archive(for: #function, mode: .create)
        do {
            try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: assetURL.path)
            let relativePath = assetURL.lastPathComponent
            let baseURL = assetURL.deletingLastPathComponent()
            try archive.addEntry(with: relativePath, relativeTo: baseURL)
            guard let entry = archive["\(assetURL.lastPathComponent)"] else {
                throw Archive.ArchiveError.unreadableArchive
            }
            guard let filePermissions = entry.fileAttributes[.posixPermissions] as? UInt16 else {
                throw CocoaError(CocoaError.fileReadUnknown)
            }
            XCTAssert(permissions == filePermissions)
        } catch {
            XCTFail("Failed to test POSIX permissions")
        }
    }

    func testArchiveCreateErrorConditions() {
        let existantURL = ZIPFoundationTests.tempZipDirectoryURL
        let nonCreatableArchive = Archive(url: existantURL, accessMode: .create)
        XCTAssertNil(nonCreatableArchive)
        let processInfo = ProcessInfo.processInfo
        var noEndOfCentralDirectoryArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        noEndOfCentralDirectoryArchiveURL.appendPathComponent(processInfo.globallyUniqueString)
        let fullPermissionAttributes = [FileAttributeKey.posixPermissions: defaultPermissions]
        let fileManager = FileManager()
        let result = fileManager.createFile(atPath: noEndOfCentralDirectoryArchiveURL.path, contents: nil,
                                                    attributes: fullPermissionAttributes)
        XCTAssert(result == true)
        let noEndOfCentralDirectoryArchive = Archive(url: noEndOfCentralDirectoryArchiveURL,
                                                     accessMode: .update)
        XCTAssertNil(noEndOfCentralDirectoryArchive)
    }

    func testArchiveUpdateErrorConditions() {
        var nonUpdatableArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        let processInfo = ProcessInfo.processInfo
        nonUpdatableArchiveURL.appendPathComponent(processInfo.globallyUniqueString)
        let noPermissionAttributes = [FileAttributeKey.posixPermissions: Int16(0o000)]
        let fileManager = FileManager()
        let result = fileManager.createFile(atPath: nonUpdatableArchiveURL.path, contents: nil,
                                            attributes: noPermissionAttributes)
        XCTAssert(result == true)
        let nonUpdatableArchive = Archive(url: nonUpdatableArchiveURL, accessMode: .update)
        XCTAssertNil(nonUpdatableArchive)
    }
}

extension Data {
    static func makeRandomData(size: Int) -> Data {
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
            let bytes = [UInt32](repeating: 0, count: size).map { _ in arc4random() }
#else
            let bytes = [UInt32](repeating: 0, count: size).map { _ in random() }
#endif
        return Data(bytes: bytes, count: size)
    }
}
