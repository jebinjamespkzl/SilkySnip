//
//  StrokeTests.swift
//  SilkySnipTests
//
//  Unit tests for Stroke model
//

import XCTest

class StrokeTests: XCTestCase {
    
    // MARK: - Basic Tests
    
    func testBasicTest() {
        // Basic test to verify test target builds
        XCTAssertTrue(true)
    }
    
    func testUUIDCreation() {
        let id = UUID()
        XCTAssertNotNil(id)
    }
    
    func testDateCreation() {
        let date = Date()
        XCTAssertNotNil(date)
    }
}
