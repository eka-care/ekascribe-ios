import XCTest
@testable import EkaScribeSDK

final class SessionManagerMapTests: XCTestCase {

    // MARK: - Helpers

    /// Decode a ScribeResultResponse from a JSON string.
    private func decodeResponse(_ json: String) throws -> ScribeResultResponse {
        try JSONDecoder().decode(ScribeResultResponse.self, from: Data(json.utf8))
    }

    // MARK: - mapToSessionResult

    func testMapEmptyResponse() {
        let response = ScribeResultResponse(data: nil)
        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)
        XCTAssertTrue(result.templates.isEmpty)
        XCTAssertNil(result.audioQuality)
    }

    func testMapResponseWithNilOutput() {
        let data = ScribeResultResponse.ResultData(
            audioMatrix: nil,
            createdAt: nil,
            output: nil,
            templateResults: nil
        )
        let response = ScribeResultResponse(data: data)
        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)
        XCTAssertTrue(result.templates.isEmpty)
    }

    func testMapSingleOutput() throws {
        let response = try decodeResponse("""
        {
            "data": {
                "output": [{
                    "name": "SOAP Notes",
                    "template_id": "t1",
                    "type": "markdown",
                    "value": "Some output"
                }]
            }
        }
        """)
        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)

        XCTAssertEqual(result.templates.count, 1)
        XCTAssertEqual(result.templates[0].name, "SOAP Notes")
        XCTAssertEqual(result.templates[0].title, "SOAP Notes")
        XCTAssertEqual(result.templates[0].templateId, "t1")
        XCTAssertEqual(result.templates[0].type, .markdown)
        XCTAssertEqual(result.templates[0].sessionId, "s1")
        XCTAssertTrue(result.templates[0].isEditable)
    }

    func testMapBase64DecodedValue() throws {
        let plainText = "Hello, World!"
        let base64Value = Data(plainText.utf8).base64EncodedString()

        let response = try decodeResponse("""
        {
            "data": {
                "output": [{
                    "name": "Notes",
                    "type": "markdown",
                    "value": "\(base64Value)"
                }]
            }
        }
        """)
        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)

        XCTAssertEqual(result.templates.count, 1)
        let section = result.templates[0].sections.first
        XCTAssertEqual(section?.value, plainText)
    }

    func testMapNonBase64Value() throws {
        let response = try decodeResponse("""
        {
            "data": {
                "output": [{
                    "name": "Notes",
                    "type": "markdown",
                    "value": "Not base64"
                }]
            }
        }
        """)
        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)

        // Non-base64 value should fall back to original value
        let section = result.templates[0].sections.first
        XCTAssertEqual(section?.value, "Not base64")
    }

    func testMapJsonType() throws {
        let response = try decodeResponse("""
        {
            "data": {
                "output": [{
                    "name": "EMR",
                    "type": "json",
                    "value": "{}"
                }]
            }
        }
        """)
        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)

        XCTAssertEqual(result.templates[0].type, .json)
    }

    func testMapAudioQuality() {
        let data = ScribeResultResponse.ResultData(
            audioMatrix: ScribeResultResponse.AudioMatrixDTO(quality: 0.85),
            createdAt: nil,
            output: [],
            templateResults: nil
        )
        let response = ScribeResultResponse(data: data)
        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)

        XCTAssertEqual(result.audioQuality, 0.85)
    }

    func testMapMultipleOutputs() throws {
        let response = try decodeResponse("""
        {
            "data": {
                "output": [
                    { "name": "Template 1", "template_id": "t1", "type": "markdown", "value": "val1" },
                    { "name": "Template 2", "template_id": "t2", "type": "json", "value": "val2" }
                ]
            }
        }
        """)
        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)

        XCTAssertEqual(result.templates.count, 2)
        XCTAssertEqual(result.templates[0].name, "Template 1")
        XCTAssertEqual(result.templates[1].name, "Template 2")
    }

    func testMapNilOutputsFiltered() {
        let data = ScribeResultResponse.ResultData(
            audioMatrix: nil, createdAt: nil,
            output: [nil, nil], templateResults: nil
        )
        let response = ScribeResultResponse(data: data)
        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)

        XCTAssertTrue(result.templates.isEmpty)
    }
}
