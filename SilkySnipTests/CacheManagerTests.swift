//
//  CacheManagerTests.swift
//  SilkySnipTests
//
//  Unit tests for CacheManager
//

import XCTest

class CacheManagerTests: XCTestCase {
    
    var testCacheURL: URL!
    
    override func setUp() {
        super.setUp()
        
        // Use a temporary directory for tests
        testCacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SilkySnipTests")
            .appendingPathComponent("Cache")
        
        try? FileManager.default.createDirectory(at: testCacheURL, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        // Clean up test cache
        try? FileManager.default.removeItem(at: testCacheURL.deletingLastPathComponent())
        
        super.tearDown()
    }
    
    // MARK: - Basic Tests
    
    func testCacheDirectoryCreation() {
        // The cache directory should exist after setup
        XCTAssertTrue(FileManager.default.fileExists(atPath: testCacheURL.path))
    }
    
    func testTemporaryDirectoryExists() {
        let tempDir = FileManager.default.temporaryDirectory
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path))
    }
}
