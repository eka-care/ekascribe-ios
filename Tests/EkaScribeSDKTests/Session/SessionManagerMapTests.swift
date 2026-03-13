import XCTest
@testable import EkaScribeSDK

final class SessionManagerMapTests: XCTestCase {

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

    func testMapSingleOutput() {
        let output = ScribeResultResponse.OutputDTO(
            errors: nil,
            name: "SOAP Notes",
            status: nil,
            templateId: "t1",
            type: "markdown",
            value: "Some output",
            warnings: nil
        )
        let data = ScribeResultResponse.ResultData(
            audioMatrix: nil,
            createdAt: nil,
            output: [output],
            templateResults: nil
        )
        let response = ScribeResultResponse(data: data)
        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)

        XCTAssertEqual(result.templates.count, 1)
        XCTAssertEqual(result.templates[0].name, "SOAP Notes")
        XCTAssertEqual(result.templates[0].title, "SOAP Notes")
        XCTAssertEqual(result.templates[0].templateId, "t1")
        XCTAssertEqual(result.templates[0].type, .markdown)
        XCTAssertEqual(result.templates[0].sessionId, "s1")
        XCTAssertTrue(result.templates[0].isEditable)
    }

    func testMapBase64DecodedValue() {
        let plainText = "Hello, World!"
        let base64Value = Data(plainText.utf8).base64EncodedString()

        let output = ScribeResultResponse.OutputDTO(
            errors: nil,
            name: "Notes",
            status: nil,
            templateId: nil,
            type: "markdown",
            value: base64Value,
            warnings: nil
        )
        let data = ScribeResultResponse.ResultData(
            audioMatrix: nil,
            createdAt: nil,
            output: [output],
            templateResults: nil
        )
        let response = ScribeResultResponse(data: data)
        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)

        XCTAssertEqual(result.templates.count, 1)
        let section = result.templates[0].sections.first
        XCTAssertEqual(section?.value, plainText)
    }

    func testMapNonBase64Value() {
        let output = ScribeResultResponse.OutputDTO(
            errors: nil,
            name: "Notes",
            status: nil,
            templateId: nil,
            type: "markdown",
            value: "Not base64!@#$",
            warnings: nil
        )
        let data = ScribeResultResponse.ResultData(
            audioMatrix: nil,
            createdAt: nil,
            output: [output],
            templateResults: nil
        )
        let response = ScribeResultResponse(data: data)
        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)

        // Non-base64 value should fall back to original value
        let section = result.templates[0].sections.first
        XCTAssertEqual(section?.value, "Not base64!@#$")
    }

    func testMapJsonType() {
        let output = ScribeResultResponse.OutputDTO(
            errors: nil,
            name: "EMR",
            status: nil,
            templateId: nil,
            type: "json",
            value: "{}",
            warnings: nil
        )
        let data = ScribeResultResponse.ResultData(
            audioMatrix: nil,
            createdAt: nil,
            output: [output],
            templateResults: nil
        )
        let response = ScribeResultResponse(data: data)
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

    func testMapMultipleOutputs() {
        let output1 = ScribeResultResponse.OutputDTO(
            errors: nil, name: "Template 1", status: nil, templateId: "t1",
            type: "markdown", value: "val1", warnings: nil
        )
        let output2 = ScribeResultResponse.OutputDTO(
            errors: nil, name: "Template 2", status: nil, templateId: "t2",
            type: "json", value: "val2", warnings: nil
        )
        let data = ScribeResultResponse.ResultData(
            audioMatrix: nil, createdAt: nil,
            output: [output1, output2], templateResults: nil
        )
        let response = ScribeResultResponse(data: data)
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
