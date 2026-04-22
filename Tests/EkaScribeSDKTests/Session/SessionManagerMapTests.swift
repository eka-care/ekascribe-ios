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

    func testMapSingleCustomOutput() throws {
        let response = try decodeResponse("""
        {
            "data": {
                "template_results": {
                    "custom": [{
                        "name": "SOAP Notes",
                        "template_id": "t1",
                        "document_id": "doc-111",
                        "document_type": "document",
                        "type": "markdown",
                        "value": "Some output",
                        "status": "success"
                    }]
                }
            }
        }
        """)
        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)

        XCTAssertEqual(result.templates.count, 1)
        XCTAssertEqual(result.templates[0].name, "SOAP Notes")
        XCTAssertEqual(result.templates[0].title, "SOAP Notes")
        XCTAssertEqual(result.templates[0].templateId, "t1")
        XCTAssertEqual(result.templates[0].documentId, "doc-111")
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
                "template_results": {
                    "custom": [{
                        "name": "Notes",
                        "type": "markdown",
                        "document_type": "document",
                        "value": "\(base64Value)",
                        "status": "success"
                    }]
                }
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
                "template_results": {
                    "custom": [{
                        "name": "Notes",
                        "type": "markdown",
                        "document_type": "document",
                        "value": "Not base64",
                        "status": "success"
                    }]
                }
            }
        }
        """)
        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)

        let section = result.templates[0].sections.first
        XCTAssertEqual(section?.value, "Not base64")
    }

    func testMapJsonType() throws {
        let response = try decodeResponse("""
        {
            "data": {
                "template_results": {
                    "custom": [{
                        "name": "EMR",
                        "type": "json",
                        "document_type": "document",
                        "value": "{}",
                        "status": "success"
                    }]
                }
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

    func testMapMultipleCustomOutputs() throws {
        let response = try decodeResponse("""
        {
            "data": {
                "template_results": {
                    "custom": [
                        { "name": "Template 1", "template_id": "t1", "document_id": "d1", "document_type": "document", "type": "markdown", "value": "val1", "status": "success" },
                        { "name": "Template 2", "template_id": "t2", "document_id": "d2", "document_type": "document", "type": "json", "value": "val2", "status": "success" }
                    ]
                }
            }
        }
        """)
        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)

        XCTAssertEqual(result.templates.count, 2)
        XCTAssertEqual(result.templates[0].name, "Template 1")
        XCTAssertEqual(result.templates[0].documentId, "d1")
        XCTAssertEqual(result.templates[1].name, "Template 2")
        XCTAssertEqual(result.templates[1].documentId, "d2")
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

    func testMapIntegrationWithDocumentId() throws {
        let response = try decodeResponse("""
        {
            "data": {
                "template_results": {
                    "integration": [{
                        "name": "Eka EMR Format",
                        "template_id": "eka_emr_template",
                        "document_id": "doc-int-1",
                        "type": "json",
                        "value": "e30=",
                        "status": "success"
                    }]
                }
            }
        }
        """)
        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)

        XCTAssertEqual(result.templates.count, 1)
        XCTAssertEqual(result.templates[0].documentId, "doc-int-1")
        XCTAssertEqual(result.templates[0].templateId, "eka_emr_template")
        XCTAssertTrue(result.templates[0].isEditable)
    }

    func testMapTranscriptWithDocumentId() throws {
        let plainText = "Patient has fever."
        let base64Value = Data(plainText.utf8).base64EncodedString()

        let response = try decodeResponse("""
        {
            "data": {
                "template_results": {
                    "transcript": [{
                        "value": "\(base64Value)",
                        "type": "transcript",
                        "status": "success",
                        "document_id": "doc-tr-1"
                    }]
                }
            }
        }
        """)
        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)

        XCTAssertEqual(result.templates.count, 1)
        XCTAssertEqual(result.templates[0].documentId, "doc-tr-1")
        XCTAssertEqual(result.templates[0].templateId, "transcript_template")
        XCTAssertFalse(result.templates[0].isEditable)
        XCTAssertEqual(result.templates[0].sections.first?.value, plainText)
    }

    func testMapCustomFiltersOutNonDocumentType() throws {
        let response = try decodeResponse("""
        {
            "data": {
                "template_results": {
                    "custom": [
                        { "name": "SOAP Notes", "template_id": "t1", "document_id": "d1", "document_type": "document", "type": "markdown", "value": "val1", "status": "success" },
                        { "name": "Add context", "template_id": "__non_tmp_doc", "document_id": "d2", "document_type": "context", "type": "markdown", "value": "val2", "status": "success" }
                    ]
                }
            }
        }
        """)
        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)

        XCTAssertEqual(result.templates.count, 1)
        XCTAssertEqual(result.templates[0].name, "SOAP Notes")
        XCTAssertEqual(result.templates[0].documentId, "d1")
    }
}
