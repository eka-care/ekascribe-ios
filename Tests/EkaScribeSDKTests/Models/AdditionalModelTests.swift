import XCTest
@testable import EkaScribeSDK

final class AdditionalModelTests: XCTestCase {

    // MARK: - ScribeSession

    func testScribeSessionInit() {
        let session = ScribeSession(
            sessionId: "s1",
            createdAt: 1000,
            updatedAt: 2000,
            state: "recording",
            chunkCount: 5,
            uploadStage: .commit
        )
        XCTAssertEqual(session.sessionId, "s1")
        XCTAssertEqual(session.createdAt, 1000)
        XCTAssertEqual(session.updatedAt, 2000)
        XCTAssertEqual(session.state, "recording")
        XCTAssertEqual(session.chunkCount, 5)
        XCTAssertEqual(session.uploadStage, .commit)
    }

    // MARK: - ScribeHistoryItem

    func testScribeHistoryItemInit() {
        let item = ScribeHistoryItem(
            bId: "bid-1",
            createdAt: "2025-01-01",
            flavour: "pro",
            mode: "dictation",
            oid: "org-1",
            processingStatus: "completed",
            txnId: "txn-1",
            userStatus: "active",
            uuid: "uuid-1",
            version: "v2",
            patientDetails: ScribePatientInfo(age: 30, biologicalSex: "M", name: "John")
        )
        XCTAssertEqual(item.bId, "bid-1")
        XCTAssertEqual(item.mode, "dictation")
        XCTAssertEqual(item.patientDetails?.age, 30)
        XCTAssertEqual(item.patientDetails?.name, "John")
    }

    func testScribeHistoryItemAllNils() {
        let item = ScribeHistoryItem()
        XCTAssertNil(item.bId)
        XCTAssertNil(item.createdAt)
        XCTAssertNil(item.patientDetails)
    }

    // MARK: - ScribePatientInfo

    func testScribePatientInfoInit() {
        let info = ScribePatientInfo(
            age: 45,
            biologicalSex: "F",
            name: "Jane",
            patientId: "p-123",
            visitId: "v-456"
        )
        XCTAssertEqual(info.age, 45)
        XCTAssertEqual(info.biologicalSex, "F")
        XCTAssertEqual(info.name, "Jane")
        XCTAssertEqual(info.patientId, "p-123")
        XCTAssertEqual(info.visitId, "v-456")
    }

    func testScribePatientInfoAllNils() {
        let info = ScribePatientInfo()
        XCTAssertNil(info.age)
        XCTAssertNil(info.biologicalSex)
        XCTAssertNil(info.name)
        XCTAssertNil(info.patientId)
        XCTAssertNil(info.visitId)
    }

    // MARK: - SessionData

    func testSessionDataInit() {
        let data = SessionData(templateId: "t-1", data: "{\"key\": \"value\"}")
        XCTAssertEqual(data.templateId, "t-1")
        XCTAssertEqual(data.data, "{\"key\": \"value\"}")
    }

    // MARK: - OutputTemplate

    func testOutputTemplateDefaultType() {
        let template = OutputTemplate(templateId: "abc-123")
        XCTAssertEqual(template.templateId, "abc-123")
        XCTAssertEqual(template.templateType, "custom")
        XCTAssertNil(template.templateName)
    }

    func testOutputTemplateCustomValues() {
        let template = OutputTemplate(templateId: "t-1", templateType: "json", templateName: "SOAP Notes")
        XCTAssertEqual(template.templateType, "json")
        XCTAssertEqual(template.templateName, "SOAP Notes")
    }

    func testOutputTemplateCodable() throws {
        let original = OutputTemplate(templateId: "t-1", templateType: "custom", templateName: "Test")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OutputTemplate.self, from: encoded)
        XCTAssertEqual(decoded.templateId, original.templateId)
        XCTAssertEqual(decoded.templateType, original.templateType)
        XCTAssertEqual(decoded.templateName, original.templateName)
    }

    // MARK: - PatientDetail

    func testPatientDetailAllNils() {
        let detail = PatientDetail()
        XCTAssertNil(detail.age)
        XCTAssertNil(detail.biologicalSex)
        XCTAssertNil(detail.name)
        XCTAssertNil(detail.patientId)
        XCTAssertNil(detail.visitId)
    }

    func testPatientDetailAllPopulated() {
        let detail = PatientDetail(age: 55, biologicalSex: "M", name: "Bob", patientId: "p1", visitId: "v1")
        XCTAssertEqual(detail.age, 55)
        XCTAssertEqual(detail.biologicalSex, "M")
        XCTAssertEqual(detail.name, "Bob")
        XCTAssertEqual(detail.patientId, "p1")
        XCTAssertEqual(detail.visitId, "v1")
    }

    // MARK: - UserConfigs

    func testUserConfigsInit() {
        let config = UserConfigs(
            consultationModes: ConsultationModeConfig(
                modes: [ConsultationMode(id: "m1", name: "Mode1", desc: "D1")],
                maxSelection: 1
            ),
            supportedLanguages: SupportedLanguagesConfig(
                languages: [SupportedLanguage(id: "en", name: "English")],
                maxSelection: 2
            ),
            outputTemplates: OutputTemplatesConfig(
                templates: [ConfigOutputTemplate(id: "t1", name: "Template1")],
                maxSelection: 3
            ),
            selectedUserPreferences: SelectedUserPreferences(),
            modelConfigs: ModelConfigs(
                modelTypes: [ModelType(id: "pro", name: "Pro", desc: "Best")],
                maxSelection: 1
            )
        )
        XCTAssertEqual(config.consultationModes.modes.count, 1)
        XCTAssertEqual(config.supportedLanguages.languages.count, 1)
        XCTAssertEqual(config.outputTemplates.templates.count, 1)
        XCTAssertEqual(config.modelConfigs.modelTypes.count, 1)
    }

    // MARK: - Individual Config Types

    func testConsultationModeInit() {
        let mode = ConsultationMode(id: "dict", name: "Dictation", desc: "Record audio")
        XCTAssertEqual(mode.id, "dict")
        XCTAssertEqual(mode.name, "Dictation")
        XCTAssertEqual(mode.desc, "Record audio")
    }

    func testSupportedLanguageInit() {
        let lang = SupportedLanguage(id: "hi-IN", name: "Hindi")
        XCTAssertEqual(lang.id, "hi-IN")
        XCTAssertEqual(lang.name, "Hindi")
    }

    func testConfigOutputTemplateInit() {
        let template = ConfigOutputTemplate(id: "soap", name: "SOAP Notes")
        XCTAssertEqual(template.id, "soap")
        XCTAssertEqual(template.name, "SOAP Notes")
    }

    func testModelTypeInit() {
        let model = ModelType(id: "pro", name: "Professional", desc: "High quality model")
        XCTAssertEqual(model.id, "pro")
        XCTAssertEqual(model.name, "Professional")
        XCTAssertEqual(model.desc, "High quality model")
    }

    func testTemplateItemInit() {
        let item = TemplateItem(
            isDefault: true,
            desc: "Default template",
            id: "t-1",
            isFavorite: false,
            sectionIds: ["s1", "s2"],
            title: "SOAP"
        )
        XCTAssertTrue(item.isDefault)
        XCTAssertEqual(item.desc, "Default template")
        XCTAssertEqual(item.id, "t-1")
        XCTAssertFalse(item.isFavorite)
        XCTAssertEqual(item.sectionIds, ["s1", "s2"])
        XCTAssertEqual(item.title, "SOAP")
    }

    // MARK: - SessionEventName Coverage

    func testSessionEventNameRawValues() {
        let names: [SessionEventName] = [
            .sessionStartInitiated, .recordingStarted, .sessionStartFailed,
            .sessionPaused, .sessionResumed, .sessionStopInitiated,
            .sessionCompleted, .sessionFailed, .audioFocusChanged,
            .modelDownloadStarted, .modelDownloadCompleted, .modelDownloadFailed,
            .modelDownloadCached, .pipelineStopped, .chunkUploaded,
            .chunkUploadFailed, .chunkProcessingFailed,
            .uploadRetryStarted, .uploadRetryCompleted,
            .initTransactionSuccess, .initTransactionFailed,
            .stopTransactionSuccess, .stopTransactionFailed,
            .commitTransactionSuccess, .commitTransactionFailed,
            .pollResultFailed, .pollResultTimeout,
            .fullAudioGenerated, .fullAudioGenerationFailed,
            .fullAudioUploaded, .fullAudioUploadFailed
        ]

        for name in names {
            XCTAssertFalse(name.rawValue.isEmpty, "SessionEventName \(name) should have non-empty rawValue")
        }
    }

    func testEventTypeRawValuesComplete() {
        XCTAssertEqual(EventType.success.rawValue, "success")
        XCTAssertEqual(EventType.error.rawValue, "error")
        XCTAssertEqual(EventType.info.rawValue, "info")
    }

    // MARK: - SelectedUserPreferences

    func testSelectedUserPreferencesDefaults() {
        let prefs = SelectedUserPreferences()
        XCTAssertNil(prefs.consultationMode)
        XCTAssertTrue(prefs.languages.isEmpty)
        XCTAssertTrue(prefs.outputTemplates.isEmpty)
        XCTAssertNil(prefs.modelType)
    }

    func testSelectedUserPreferencesPopulated() {
        let prefs = SelectedUserPreferences(
            consultationMode: ConsultationMode(id: "c1", name: "Consult", desc: ""),
            languages: [SupportedLanguage(id: "en", name: "English")],
            outputTemplates: [ConfigOutputTemplate(id: "t1", name: "Template")],
            modelType: ModelType(id: "pro", name: "Pro", desc: "Best")
        )
        XCTAssertNotNil(prefs.consultationMode)
        XCTAssertEqual(prefs.languages.count, 1)
        XCTAssertEqual(prefs.outputTemplates.count, 1)
        XCTAssertNotNil(prefs.modelType)
    }
}
